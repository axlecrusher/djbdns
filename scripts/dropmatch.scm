#!/bin/sh
set -e || exit "$?" # -*- scheme -*-
case $ZSH_VERSION in ?*) alias -g '${1+"$@"}="$@"';; esac
exec "${GUILE-guile}" -e main -s "$0" ${1+"$@"}
!#

;; Output format is:
;; nanoseconds-spent-working-on-dropped-query query-type query-name

;;(read-enable 'positions)
(debug-enable 'backtrace)
(debug-enable 'debug)

(use-modules (srfi srfi-2))
(use-modules ((srfi srfi-13) :select (string-tokenize string-prefix?)))
(use-modules ((ice-9 ftw)    :select (directory-files)))
(use-modules ((ice-9 rdelim) :select (read-line)))

;;(load "/package/prog/prjlibs/scheme/load.scm")
;;(/package/prog/prjlibs/load
;; "/package/prog/prjlibs/scheme/errors.scm"
;; '(exit-for-system-error))

(define-macro (defloop loopname var feeder pred . forms)
  `(let ,loopname ()
        (let ((,var ,feeder))
          (if ,pred
            (begin
              (let* . ,forms)
              (,loopname))))))

(define (process queries port)
  (defloop lineloop line (read-line port) (not (eof-object? line))
    ((fields (string-tokenize line))
     (op (string->symbol (list-ref fields 1)))
     (query (and (not (null? (cddr fields))) (list-ref fields 2)))
     (stamp (substring (list-ref fields 0) 1))
     (stamp (+ (* 1000000000 (string->number (substring stamp 0 16) 16))
               (string->number (substring stamp 16) 16))))
    (case op
      ((query)
       (hash-set! queries query
                  (list (list-ref fields 5) (list-ref fields 4) stamp)))
      ((drop)
       (and-let* ((dummy (equal? '("timed" "out") (cdddr fields)))
                  (data (hash-ref queries query))
                  (qname     (list-ref data 0))
                  (qtype     (list-ref data 1))
                  (old-stamp (list-ref data 2)))
         (hash-remove! queries query)
         (format #t "~S ~A ~A\n" (- stamp old-stamp) qtype qname))))))

(define (main args)
  ;;(define (do-it)
    (if (null? (cdr args))
      (let ((queries (make-hash-table 661))
            (oldstate (fdopen 4 "r"))
            (newstate (fdopen 5 "w")))
        (defloop old-input qrec (read oldstate) (not (eof-object? qrec))
          ()
          (hash-set! queries (car qrec) (cdr qrec)))
        (process queries (current-input-port))
        (hash-fold (lambda (key val accum)
                     (write (cons key val) newstate)
                     (newline newstate))
                   #f
                   queries)
        (force-output newstate))
      (for-each
       (lambda (dir)
         (define queries (make-hash-table 661))
         (for-each
          (lambda (file)
            (if (or (string=? file "current") (string-prefix? "@" file))
              (process queries (open (string-append dir "/" file) O_RDONLY))))
          (sort (directory-files dir) string<?)))
       (cdr args)))
    (force-output (current-output-port))
    ;;)
  ;;(exit-for-system-error "dropmatch" do-it)
  )
