#lang racket
(require racket/generator)
(define (R0? sexp)
  (match sexp
    [(? exact-integer?) sexp]
    [`(read) (let ([r (read)]) (cond [(exact-integer? r) r] [else (error 'R0? "Not an integer" r)]))]
    [`(- ,(app R0? e)) (- 0 e) ]
    [`(+ ,(app R0? c1) ,(app R0? c2)) (+ c1 c2)]
    [`(program ,e) (R0? e)]
    [else #f]))

(define (intrp-R1 env)
  (lambda (e)
    (define recur (intrp-R1 env))
    (match e
      [(? symbol?)(lookup e env)]
      
      [(? exact-integer?) e]
      [`(read)
       (define r (read))
       (cond [(exact-integer? r) r]
             [else (error `intrp-R1 "Expected integer" r)])]
      [`(- ,(app recur v))
       (- 0 v)]
      [`(+ ,(app recur v1) ,(app recur v2)) (+ v1 v2)]
      [`(program ,e) ((intrp-R1 '()) e)])))
