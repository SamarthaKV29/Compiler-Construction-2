#lang racket
(define (fact n) (if (zero? n) 1 (* n (fact (sub1 n)))))
(require plot)
(plot
 (list
  (function λ (x) (for ([x 100])
  (time (fact x))
  )))
 #:x-min 0
      #:y-min 0
      #:x-max 10
      #:y-max 100
 )
 