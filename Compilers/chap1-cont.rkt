#lang racket
(require racket/fixnum)
(define (pe-neg r)
  (cond [(fixnum? r) (fx- 0 r)]
        [else `(- ,r)]))


(define (pe-add r1 r2)
  (cond [(and (fixnum? r1) (fixnum? r2)) (fx+ r1 r2)]
        [else `(+ ,r1 ,r2)]))

(pe-neg 5)
(pe-add 5 6)
(define (pe-arith e)
(match e
  [(? fixnum?) e]
  [`(read) `(read)]
  [`(- ,(app pe-arith r1))(pe-neg r1)]
  ))

(pe-arith 10)

