#lang racket

(define (combine paper midterm pres final)
    (+ (* 0.2 paper) (* 0.2 midterm)
       (* 0.3  pres) (* 0.3   final)))

(define (cnvl paper midterm pres final)

  (define ng (combine paper midterm pres final))
  (cond
      [(> ng 0.93) "A"]
      [(> ng 0.9) "A-"]
      [(> ng 0.86) "B+"]
      [(> ng 0.83) "B"]
      [(> ng 0.8) "B-"]
      [(> ng 0.76) "C+"]
      [(> ng 0.73) "C"]
      [(> ng 0.7) "C-"]
      [(> ng 0.66) "D+"]
      [(> ng 0.6) "D"]
      [else "F"])
  )