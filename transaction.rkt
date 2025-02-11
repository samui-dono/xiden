#lang racket/base

; Consider the following command line, where -i and -u can be
; specified multiple times.
;
;  $ ... -i a -u b -i c -u d
;
; The user expects the command to handle arguments in the shown
; order: (a b c d).  This module does so in a transactional
; control flow.

(require racket/contract
         racket/exn
         "cli-flag.rkt"
         "message.rkt"
         "subprogram.rkt")

(provide
 (contract-out
  [transact
   (-> (listof (-> subprogram?))
       (-> list? any)
       (-> list? any)
       any)]
  [fold-transaction-actions
   (-> (listof cli-flag-state?)
       (hash/c procedure? (-> any/c subprogram?))
       (listof (-> subprogram?)))]))

(define (transact actions commit rollback)
  (call/cc
   (λ (k)
     (define (done messages) (k (commit messages)))
     (define (fail messages) (k (rollback messages)))

     (commit
      (for/fold ([accum-messages null])
                ([action (in-list actions)])
        (define-values (result messages)
          (with-handlers
            ([$message?
              (λ (m)
                (fail (cons m accum-messages)))]
             [(λ _ #t)
              (λ (e)
                (fail (cons ($show-string (exn->string e))
                            accum-messages)))])
            (run-subprogram (action) accum-messages)))

        (if (eq? result FAILURE)
            (fail messages)
            messages))))))


(define (fold-transaction-actions flags lookup)
  (fold-transaction-actions-aux flags lookup null (hasheq)))


(define (fold-transaction-actions-aux flags lookup actions counts)
  (if (null? flags)
      (reverse actions)
      (let ([setting (cli-flag-setting (cli-flag-state-flag-definition (car flags)))])
        (if (hash-has-key? lookup setting)
            (add-action flags
                        lookup
                        actions
                        setting
                        (hash-set counts setting (add1 (hash-ref counts setting -1))))
            (fold-transaction-actions-aux (cdr flags)
                                          lookup
                                          actions
                                          counts)))))

(define (make-action lookup setting value)
  (λ () ((hash-ref lookup setting) value)))


(define (add-action flags lookup actions setting counts)
  (fold-transaction-actions-aux (cdr flags)
                                lookup
                                (cons (make-action lookup
                                                   setting
                                                   (list-ref (setting)
                                                             (hash-ref counts setting)))
                                      actions)
                                counts))


(module+ test
  (require rackunit
           racket/format
           racket/list
           racket/match
           "setting.rkt")


  (define-setting TEST_LETTER_STRINGS  list? null)
  (define-setting TEST_NUMBER_STRINGS  list? null)
  (define-setting TEST_RED_HERRING     list? null)

  (define str-flag (cli-flag TEST_LETTER_STRINGS 'multi '("-l") 1 void '("any")))
  (define num-flag (cli-flag TEST_NUMBER_STRINGS 'multi '("-n") 1 void '("any")))
  (define red-flag (cli-flag TEST_RED_HERRING    'multi '("-h") 1 void '("any")))

  ; Use to produce mock cli flag handler values.
  (define (mocker value-list flag)
    (λ (i) (cli-flag-state (shortest-cli-flag flag)
                           flag
                           (list-ref value-list i))))
  (define (act v)
    (subprogram-attachment (eq? v 'b)
                           ($show-string (~a v))))

  (call-with-applied-settings
   (hash TEST_LETTER_STRINGS '(a b c)
         TEST_NUMBER_STRINGS '(1 2 3)
         TEST_RED_HERRING    '("red"))
   (λ ()
     (define mock-letter  (mocker (TEST_LETTER_STRINGS) str-flag))
     (define mock-number  (mocker (TEST_NUMBER_STRINGS) num-flag))
     (define mock-herring (mocker (TEST_RED_HERRING)    red-flag))

     (define flags
       (list (mock-letter  0)
             (mock-number  0)
             (mock-herring 0)
             (mock-herring 0)
             (mock-number  1)
             (mock-herring 0)
             (mock-letter  1)
             (mock-herring 0)
             (mock-letter  2)
             (mock-number  2)))

     (define actions
       (fold-transaction-actions flags
                                 (hasheq TEST_LETTER_STRINGS symbol->string
                                         TEST_NUMBER_STRINGS -)))

     (define expected-preprocessed-values
       '("a" -1 -2 "b" "c" -3))

     (test-equal? "Bind multi flags in thunks"
                  (map (λ (f) (f)) actions)
                  expected-preprocessed-values)

     (test-case "Carry out successful transaction"
       (define (rollback m)
         (cons 'rolled-back (flatten m)))

       (check-equal? (transact (map (λ (f) (λ () (subprogram-attachment (f) ($show-string (~a (f)))))) actions)
                               flatten
                               rollback)
                     (map (compose $show-string ~a)
                          (reverse expected-preprocessed-values)))

       (define (warn) (subprogram-attachment #f ($show-string "about to fail")))
       (test-equal? "Handle transaction failure"
                    (transact (list warn
                                    (λ () (subprogram-failure ($show-string "uh oh")))
                                    warn)
                              flatten
                              rollback)
                    (list 'rolled-back
                          ($show-string "uh oh")
                          ($show-string "about to fail")))

       (test-equal? "Handle transaction failure via raised value"
                    (transact (list warn (λ () (raise 'oops)) warn)
                              flatten
                              rollback)
                    (list 'rolled-back
                          ($show-string "oops\n")
                          ($show-string "about to fail")))))))
