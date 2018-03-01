#lang racket
(require pict)

(define pcir (circle 50))
(define prec (rectangle 10 10))
(define prec2 (rectangle 40 50))
(define combined (hc-append 20 prec pcir))
(pin-line combined prec rc-find pcir lc-find)
(define combined2 (vc-append 20 prec2 pcir))
(pin-arrow-line 5 combined2 prec2 cc-find pcir cc-find)