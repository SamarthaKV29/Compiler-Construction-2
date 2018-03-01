#lang racket
(define mylist (list (range 1 10)))

(define (bake flav)
  (string-append flav "jell"))

(bake "apple")

(if (> (read) (read))
      "bigger"
      "smaller")