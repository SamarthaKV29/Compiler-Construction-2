#lang racket
(require racket/fixnum)
(require "utilities.rkt")



(define (r0 prog)
  (match prog
    [(regexp #rx"print [a-z]*" prog) (write prog)]
    [()]))



(r0 "print x")
