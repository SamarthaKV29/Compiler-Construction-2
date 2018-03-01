#lang racket
(require racket/pretty)
(require (for-syntax racket))
(provide debug-level at-debug-level? debug verbose vomit
         map2 map3 b2i i2b
         racket-id->c-id
         hash-union set-union*
         fix while 
         label-name lookup  make-dispatcher assert
         read-fixnum read-program 
	 compile compile-file check-passes interp-tests compiler-tests
	 make-graph add-edge adjacent vertices print-dot
         use-minimal-set-of-registers!
	 general-registers registers-for-alloc caller-save callee-save
	 arg-registers rootstack-reg register->color registers align
         byte-reg->full-reg print-by-type strip-has-type)

;; debug state is a nonnegative integer.
;; The easiest way to increment it is passing the -d option
;; to run-tests.rkt
;; 0 none 
;; 1 trace passes in run-test
;; 2 debug macros
;; 3 verbose debugging
;; 4 (vomit) absolutely everything
;; The higher the setting the more information is reported.
;; If you want the same functionality as previous incarnation
;; of utilities then uncomment the line after this definition
;; and change the number there.
(define debug-level
  (make-parameter
   0
   (lambda (d)
     (unless (exact-nonnegative-integer? d) 
       (error 'debug-state "expected nonnegative-integer in ~a" d))
     d)))
;; (debug-level 2)

;; Check to see if debug state is at least some level
(define (at-debug-level? n)
  (unless (exact-nonnegative-integer? n)
    (error 'at-debug-level? "expected non-negative integer ~a" n))
  (>= (debug-level) n))

;; print-label-and-values prints out the label followed the values
;; and the expression that generated those values
;; The label is formated with the file and line number of the
;; debubing expression for easier location.
(define-syntax (print-label-and-values stx)
  (syntax-case stx ()
    [(_ label value ...)
     (let* ([src (syntax-source stx)]
            [src (if (path? src)
                     (find-relative-path (current-directory) src)
                     src)]
            [lno (syntax-line stx)])
       #`(begin
           (printf "~a @ ~a:~a\n" label #,src #,lno)
        (begin
          (printf "~a:\n" 'value)
          (if (string? value)
              (display value)
              (pretty-print value))
          (newline))
        ...
        (newline)))]))

;; This series of macros are used for debuging purposes
;; and print out
(define-syntax-rule (define-debug-level name level)
    (...
     (define-syntax (name stx)
      (syntax-case stx ()
        [(_ label value ...)
         #`(when (at-debug-level? level)
             #,(syntax/loc stx
                 (print-label-and-values label value ...)))]))))

;; Print out debugging info in a somewhat organized manner
;; (debug "foo" (car '(1 2)) 'foo) should print
;; foo @ utilities.rkt:77
;; (car '(1 2)):
;; 1
;; 'foo:
;; foo
(define-debug-level trace 1)
(define-debug-level debug 2)
(define-debug-level verbose 3)
(define-debug-level vomit 4)

(define-syntax-rule (while condition body ...)
  (let loop ()
    (when condition
      body ...
      (loop))))

(define fix (lambda (f) (lambda (x) ((f (fix f)) x))))

;; These functions convert between booleans and integers in
;; the regular C convention
(define (i2b i)
  (cond [(eq? i 0) #f]
        [else #t]))

(define (b2i b)
  (cond [b 1]
        [else 0]))

;; This function is like map but the function f returns
;; two values using the ``values'' form. Thus, the result
;; of map2 is two lists.
(define (map2 f ls)
  (cond [(null? ls)
         (values '() '())]
        [else
         (let-values ([(x1 x2) (f (car ls))]
                      [(ls1 ls2) (map2 f (cdr ls))])
           (values (cons x1 ls1) (cons x2 ls2)))]))

(define (map3 f ls)
  (cond [(null? ls)
         (values '() '() '())]
        [else
         (let-values ([(x1 x2 x3) (f (car ls))]
                      [(ls1 ls2 ls3) (map3 f (cdr ls))])
           (values (cons x1 ls1) (cons x2 ls2) (cons x3 ls3)))]))

;; set-union* takes a list of sets and unions them all together.
(define (set-union* ls)
  (foldl set-union (set) ls))

(define (hash-union . hs)
  (for*/hash ([h (in-list hs)]
              [(k v) (in-hash h)])
    (values k v)))

;; label-name prepends an underscore to a label (symbol or string)
;; if the current system is Mac OS and leaves it alone otherwise.
;; label-name : (U String Symbol) -> String
(define (label-name name)
  (unless (or (symbol? name) (string? name))
    (error 'label-name "expected string or symbol got ~s" name))
  (cond
    [(symbol? name) (label-name (symbol->string name))]
    [(eqv? (system-type 'os) 'macosx) (string-append "_" name)]
    [else name]))

;; The lookup function takes a key and an association list
;; and returns the corresponding value. It triggers an
;; error if the key is not present in the association list.
;;   
;; The association list may be constructed of either
;; immutable or mutable pairs.
;;
(define no-default (gensym))

(define (lookup x ls [default no-default])
  (let recur ([xs ls])
    (cond
      [(null? xs)
       (if (eq? default no-default)
           (error 'lookup "didn't find ~a in ~a" x ls)
           default)]
      [(pair? xs)
       (define fst (car xs))
       (cond
         [(and (pair?  fst) (equal? x (car  fst))) (cdr  fst)]
         [(and (mpair? fst) (equal? x (mcar fst))) (mcdr fst)]
         [(or (pair? fst) (mpair? fst)) (recur (cdr xs))]
         [else (error 'lookup "expected pair for ~a in ~a" fst ls)])]
      [else (error 'lookup "expected an association list in ~a" ls)])))

(define (read-fixnum)
  (define r (read))
  (cond [(fixnum? r) r]
	[else (error 'read "expected an integer")]))

;; Read an entire .rkt file wrapping the s-expressions in
;; a list whose head is 'program.
(define (read-program path)
  (unless (or (string? path) (path? path))
    (error 'read-program "expected a string in ~s" path))
  (unless (file-exists? path)
    (error 'read-program "file doesn't exist in ~s" path))
  (debug "utilities/read-program" path)
  (define input-prog
    (call-with-input-file path
      (lambda (f)
        `(program . ,(for/list ([e (in-port read f)]) e)))))
  (debug "utilities/read-program" input-prog)
  input-prog)

(define (make-dispatcher mt)
  (lambda (e . rest)
    (match e
       [`(,tag ,args ...)
	(apply (hash-ref mt tag) (append rest args))]
       [else
	(error "no match in dispatcher for " e)]
       )))

;; The check-passes function takes a compiler name (a string), a
;; typechecker (see below), a description of the passes (see below),
;; and an initial interpreter to apply to the initial expression, and
;; returns a function that takes a test name and runs the passes and
;; the appropriate interpreters to test the correctness of all the
;; passes. This function assumes there is a "tests" subdirectory and a
;; file in that directory whose name is the test name followed by
;; ".rkt". Also, there should be a matching file with the ending ".in"
;; that provides the input for the Scheme program. If any program
;; should not pass typechecking, then there is a file with the name
;; number (whose contents are ignored) that ends in ".tyerr".
;;
;; The description of the passes is a list with one entry per pass.
;; An entry is a list with three things: a string giving the name of
;; the pass, the function that implements the pass (a translator from
;; AST to AST), and a function that implements the interpreter (a
;; function from AST to result value).
;;
;; The typechecker is a function of exactly one argument that EITHER
;; raises an error using the (error) function when it encounters a
;; type error, or returns #f when it encounters a type error. 

(define (strip-has-type e)
  (match e 
    [`(has-type ,e ,T)
     (strip-has-type e)]
    [`(,(app strip-has-type e*) ...)
      `(,@e*)]
    [else
     e]))

(define (check-passes name typechecker passes initial-interp)
  (lambda (test-name)
    (debug "** compiler " name)
    (debug "** checking passes for test " test-name)
    (define input-file-name (format "tests/~a.in" test-name))
    (define result-file-name (format "tests/~a.res" test-name))
    (define program-name (format "tests/~a.rkt" test-name))
    (define sexp (read-program program-name))
    (debug "check passes:" sexp)
    (define type-error-expected (file-exists? (format "tests/~a.tyerr" test-name)))
    (define tsexp (test-typecheck typechecker sexp))    
    (cond
     [(and type-error-expected tsexp)
      (error (format "expected type error in compiler '~a', case ~a, but no error raised by typechecker" name test-name))]
     [type-error-expected 'expected-type-error]
     [tsexp 
      (let loop ([passes passes] [p tsexp]
                 [result (cond [initial-interp
                                (if (file-exists? input-file-name)
                                    (with-input-from-file input-file-name
                                      (lambda () (initial-interp tsexp)))
                                    (initial-interp tsexp))]
                               [else 
                                (if (file-exists? result-file-name)
                                    (call-with-input-file result-file-name
                                      (lambda (f) (string->number (read-line f))))
                                    42)])])
        (cond [(null? passes)  result]
              [else
               (match (car passes)
                 [`(,pass-name ,pass ,interp)
                  (let ([input p])
                    (debug (string-append "running pass: " pass-name
					  " on test: " test-name)
                           input))
                  (define new-p (pass p))
                  (let ([output new-p])
                    (trace (string-append "running pass: " pass-name
					  " on test: " test-name)
                           output))
                  (cond [interp
                         (let ([new-result
                                ;; if there is an input file with the same name
                                ;; as this test bind current-input-port to that
                                ;; file's input port so that the interpreters
                                ;; can use it as test input.
                                (if (file-exists? input-file-name) 
                                    (with-input-from-file input-file-name
                                      (lambda () (interp new-p)))
                                    (interp new-p))])
                           
                           (cond [result
                                  (cond [(equal? result new-result)
                                         (loop (cdr passes) new-p new-result)]
                                        [else
                                         (display "in program")(newline)
                                         (pretty-print new-p)(newline)
                                         (error 'check-passes
                                                "differing results in compiler '~a' on test '~a' pass '~a', expected ~a, not ~a"
                                                name test-name pass-name result
                                                new-result
                                                )])]
                                 [else ;; no result to check yet
                                  (loop (cdr passes) new-p new-result)]))]
                        [else
                         (loop (cdr passes) new-p result)])])]))]
     [else (error 'check-passes "unexpected type error raised by compiler '~a'" name)])))


(define (compile passes)
  (let ([prog-file-name (vector-ref (current-command-line-arguments) 0)])
    ((compile-file passes) prog-file-name)))

;; The compile-file function takes a typechecker and a description of
;; the compiler passes (see the comment for check-passes) and returns
;; a function that, given a program file name (a string ending in
;; ".rkt") that passes typechecking, applies all of the passes and
;; writes the output to a file whose name is the same as the proram
;; file name but with ".rkt" replaced with ".s". The function then
;; returns #t. If the program does not typecheck, the returned
;; function will return #f.
(define (compile-file typechecker passes)
  (lambda (prog-file-name)
    (define file-base (string-trim prog-file-name ".rkt"))
    (define out-file-name (string-append file-base ".s"))
    (call-with-output-file
      out-file-name
      #:exists 'replace
      (lambda (out-file)
        (define sexp (read-program prog-file-name))
        (define tsexp (test-typecheck typechecker sexp))
        (if tsexp
            (let ([x86 (let loop ([passes passes] [p tsexp])
                         (cond [(null? passes) p]
                               [else
                                (match (car passes)
                                  [`(,name ,pass ,interp)
                                   (let ([new-p (pass p)])
				     (trace (string-append "running pass: "
							   name)
					    (strip-has-type new-p))
                                     (loop (cdr passes) new-p)
                                     )])]))])
              (cond [(string? x86)
                     (write-string x86 out-file)
                     (newline out-file)
                     (flush-output out-file)
                     #t]
                    [else
                     (error "compiler did not produce x86 output")])
              )
            #f)
        ))))

;; The interp-tests function takes a compiler name (a string), a
;; typechecker (see the comment for check-passes) a description of the
;; passes (ditto) a test family name (a string), and a list of test
;; numbers, and runs the compiler passes and the interpreters to check
;; whether the passes correct.
;; 
;; This function assumes that the subdirectory "tests" has a bunch of
;; Scheme programs whose names all start with the family name,
;; followed by an underscore and then the test number, ending in
;; ".rkt". Also, for each Scheme program there is a file with the same
;; number except that it ends with ".in" that provides the input for
;; the Scheme program. If any program should not pass typechecking,
;; then there is a file with the name number (whose contents are
;; ignored) that ends in ".tyerr".

(define (interp-tests name typechecker passes initial-interp test-family test-nums)
  (define checker (check-passes name typechecker passes initial-interp))
  (for ([test-number (in-list test-nums)])
    (let ([test-name (format "~a_~a" test-family test-number)])
      (debug "utilities/interp-test" test-name)
      (checker test-name))))

;; The compiler-tests function takes a compiler name (a string), a
;; typechecker (see the comment for check-passes) a description of the
;; passes (ditto), a test family name (a string), and a list of test
;; numbers (see the comment for interp-tests), and runs the compiler
;; to generate x86 (a ".s" file) and then runs gcc to generate machine
;; code, unless a type error is detected. It runs the machine code and
;; stores the result. If the test file has a corresponding .res file,
;; the result is compared against its contents; otherwise, the result
;; is compared against 42. If a type error is detected, it will check
;; if a .tyerr file exists, and report an error if not. It will do the
;; same if a .tyerr file exists but the typechecker does not report an
;; error.

(define (compiler-tests name typechecker passes test-family test-nums)
  (define compiler (compile-file typechecker passes))
  (debug "compiler-tests starting" '())
  (for ([test-number (in-list test-nums)])
    (define test-name  (format "~a_~a" test-family test-number))
    (debug "compiler-tests, testing:" test-name)
    (define type-error-expected (file-exists? (format "tests/~a.tyerr" test-name)))
    (define typechecks (compiler (format "tests/~a.rkt" test-name)))
    (if (and (not typechecks) (not type-error-expected))
        (error (format "test ~a failed, unexpected type error" test-name)) 
        '())
    (if typechecks
        (if (system (format "gcc -g -std=c99 runtime.o tests/~a.s" test-name))
            (void) (exit))
        '())
    (let* ([input (if (file-exists? (format "tests/~a.in" test-name))
                      (format " < tests/~a.in" test-name)
                      "")]
           [output (if (file-exists? (format "tests/~a.res" test-name))
                       (call-with-input-file
                         (format "tests/~a.res" test-name)
                         (lambda (f) (read-line f)))
                       "42")]
           [progout (if typechecks (process (format "./a.out~a" input)) 'type-error)]
           )
      ;; process returns a list, it's first element is stdout
      (match progout
        ['type-error (display test-name) (display " ") (flush-output)] ;already know we don't have a false positive
        [`(,in1 ,out ,_ ,in2 ,control-fun)
         (if type-error-expected
             (error (format "test ~a passed typechecking but should not have." test-name)) '())
         (control-fun 'wait)
         (cond [(eq? (control-fun 'status) 'done-ok)
                (let ([result (read-line (car progout))])
		  (unless (not (eq? result eof))
			  (error "error: program did not produce output"))
                  (if (eq? (string->symbol result) (string->symbol output))
                      (begin (display test-name)(display " ")(flush-output))
                      (error (format "test ~a failed, output: ~a, expected ~a" 
                                     test-name result output))))]
               [else
                (error
                 (format "test ~a error in x86 execution, exit code: ~a" 
                         test-name (control-fun 'exit-code)))])
         (close-input-port in1)
         (close-input-port in2)
         (close-output-port out)])
      )))


;; Takes a function of 1 argument (or #f) and Racket expression, and
;; returns whether the expression is well-typed. If the first argument
;; is #f, that means we aren't providing a typechecker so we simply
;; return true. If not, we apply the typechecker to the expression. We
;; require that a typechecker will EITHER raise an error using the
;; (error) function when it encounters a type error, or that it
;; returns #f when it encounters a type error. This function then
;; returns whether a type error was encountered.
(define (test-typecheck tcer exp)
  (define (handler e)
    (vomit "test-typecheck" tcer exp e)
    (when (at-debug-level? 1)
	  (display (exn-message e))
	  (newline)(newline))
    #f)
  (if (eq? tcer #f)
      exp
      (let ([res (with-handlers ([exn:fail? handler])
                   (tcer exp))])
        (match res
          [#f #f]
          [`(program ,elts ...) res]
          [else exp]))))

(define assert
  (lambda (msg b)
    (if (not b)
	(begin
	  (display "ERROR: ")
	  (display msg)
	  (newline))
	(void))))

;; (case-> (symbol . -> . symbol) (string . -> . string))
(define (racket-id->c-id x)
  (define (->c-id-char c)
    (if (or (char<=? #\A c #\Z)
            (char<=? #\a c #\z)
            (char<=? #\0 c #\9))
        c
        #\_))
  (cond
    [(symbol? x) (string->symbol (racket-id->c-id (symbol->string x)))]
    [(string? x) (list->string (map ->c-id-char (string->list x)))]
    [else (error 'racket-id->c-id "expected string or symbol: ~v" x)]))


;; System V Application Binary Interface
;; AMD64 Architecture Processor Supplement
;; Edited by Jan Hubicˇka, Andreas Jaeger, Mark Mitchell
;; December 2, 2003

;; We reserve rax and r11 for patching instructions.
;; We reserve r15 for the rootstack pointer. 
(define rootstack-reg 'r15)
;; There are 11 other general registers:
(define general-registers (vector 'rbx 'rcx 'rdx 'rsi 'rdi
    				  'r8 'r9 'r10 'r12 
				  'r13 'r14))

(define arg-registers (void))
(define registers-for-alloc (void))

;; registers-for-alloc should always inlcude the arg-registers.
(define (use-minimal-set-of-registers! f)
  (if f
      (begin
        (set! arg-registers (vector 'rcx))      
        (set! registers-for-alloc (vector 'rbx 'rcx)))
      (begin
        (set! arg-registers   (vector 'rdi 'rsi 'rdx 'rcx 'r8 'r9))
        (set! registers-for-alloc general-registers))))

(use-minimal-set-of-registers! #f)

;; We don't need to include the reserved registers
;; in the list of caller or callee save registers.
(define caller-save (set 'rdx 'rcx 'rsi 'rdi 'r8 'r9 'r10))
(define callee-save (set 'rbx 'r12 'r13 'r14))



(define byte-register-table
  (make-immutable-hash
   `((ah . rax) (al . rax)
     (bh . rbx) (bl . rbx)
     (ch . rcx) (cl . rcx)
     (dh . rdx) (dl . rdx))))

(define (byte-reg->full-reg x)
  (let ([r? (hash-ref byte-register-table x #f)])
    (unless r?
      (error 'byte-reg->full-reg "invalid byte register ~a" x))
    r?))

;; The positive numbers here correspond to indices in the general-registers
;; and registers-for-alloc.
(define reg-colors
  '((rax . -1) (r11 . -2) (r15 . -3) (rbp . -4) (__flag . -5)
    (rbx . 0) (rcx . 1) (rdx . 2) (rsi . 3) (rdi . 4)
    (r8 . 5) (r9 . 6) (r10 . 7) (r12 . 8) (r13 . 9)
    (r14 . 10)))

(define (register->color r)
  (cdr (assq r reg-colors)))

(define registers (set-union (list->set (vector->list general-registers))
			     (set 'rax 'r11 'r15 'rsp 'rbp '__flag)))

(define (align n alignment)
  (cond [(eq? 0 (modulo n alignment))
	 n]
	[else
	 (+ n (- alignment (modulo n alignment)))]))


; Produces a string containing x86 instructions that print whatever is
; currently in %rax. Will clobber the contents of (potentially)
; r12-r15, so this should only be used at the end of a program (and
; before moving 0 to rax).  Note that the "[depth 12]" part here is an
; optional argument, which is used internally.  Call this function
; with a single argument, like (print-by-type '(Vector Integer
; Boolean)).  If you try to print nested vectors that are more than 4
; levels deep, the 5th vector will be printed as #(...).
(define (print-by-type ty [depth 12])
  (define (mov-and-print depth) 
    (lambda (ty index)
      (format "\tmovq\t~a(%r~a), %rax\n~a" (* 8 (+ 1 index)) depth (print-by-type ty (+ 1 depth)))))
  (match ty
    ['Any 
     (format "\tmovq\t%rax, %rdi\n\tcallq\t~a\n" (label-name "print_any"))]
    ['Void (format "\tcallq\t~a\n" (label-name "print_void"))]
    ['Integer 
     (format "\tmovq\t%rax, %rdi\n\tcallq\t~a\n" (label-name "print_int"))]
    ['Boolean 
     (format "\tmovq\t%rax, %rdi\n\tcallq\t~a\n" (label-name "print_bool"))]
    [`(Vector ,tys ...)
     (if (> depth 15)
         (format "\tmovq\t%rax, %rdi\n\tcallq\t~a\n" (label-name "print_ellipsis"))
         (string-join (map (mov-and-print depth) tys (range (length tys)))
                      (format "\tcallq\t~a\n" (label-name "print_space"))
                      #:before-first (format "\tmovq\t%rax, %r~a\n\tcallq\t~a\n" depth (label-name "print_vecbegin"))
                      #:after-last (format "\tcallq\t~a\n" (label-name "print_vecend"))))]))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Graph ADT

(define (make-graph vertices)
  (make-hash (map (lambda (v) (cons v (set))) vertices)))

(define (add-edge graph u v)
  (hash-set! graph u (set-add (hash-ref graph u (set)) v))
  (hash-set! graph v (set-add (hash-ref graph v (set)) u)))

(define (adjacent graph u)
  (hash-ref graph u))

(define (vertices graph)
  (hash-keys graph))

(define (print-dot graph file-name)
  (if (at-debug-level? 1)
      (call-with-output-file file-name #:exists 'replace
	(lambda (out-file)
	  (write-string "strict graph {" out-file) (newline out-file)
	  
	  (for ([v (vertices graph)])
	       (write-string (format "~a;\n" v) out-file))
	  
	  (for ([v (vertices graph)])
	       (for ([u (adjacent graph v)])
		    (write-string (format "~a -- ~a;\n" u v) out-file)))
	  
	  (write-string "}" out-file)
	  (newline out-file)))
      '()))
      