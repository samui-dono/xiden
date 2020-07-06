#lang racket

(provide start-server)

(require racket/exn
         racket/runtime-path
         web-server/http
         web-server/web-server
         (prefix-in seq:
                    web-server/dispatchers/dispatch-sequencer)
         (prefix-in logged:
                    web-server/dispatchers/dispatch-log)
         (prefix-in lift:
                    web-server/dispatchers/dispatch-lift)
         "catalog.rkt"
         "endpoint.rkt")

(define (not-found req)
  (response/output #:code 404
                   #:mime-type #"text/plain; charset=utf-8"
                   (λ (o) (displayln "Resource not found." o))))

(define (start-server)
  (serve #:port (url-port (make-endpoint))
         #:dispatch
         (seq:make
          (logged:make #:format logged:extended-format #:log-path (current-output-port))
          catalog-dispatcher
          (lift:make not-found))))
