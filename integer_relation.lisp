;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Integer relations package
;;
;; Copyright: 2006, Andrej Vodopivec
;; Licence:   GPL
;;
;;   Integer relation package implements pslq algorithm to find integer
;;   relations between bigfloat numbers.
;;
;; Description:
;;
;;   For a given vector x of floating point numbers we want to find a
;;   vector of integers m such that m.x=0 (in given precision).
;;
;;   Uses PLSQ algorithm:
;;     D.H.Bailey: Integer Relation Detection and Lattice Reduction.
;;
;;;;;;;;;;;;;;;;;;

(in-package :maxima)
(macsyma-module integer_relation)

($put '$integer_relation 1.0 '$version)

(defmfun $integer_relation (l)
  (if (not ($listp l))
      (merror "Argument to `integer_relation' not a list."))
  (let* ((n ($length l)) (l (cdr l)) (a (make-array n)) ($float2bf t))
    (loop for i from 0 to (1- n) do
         (let ((elm (car l)))
           (if ($floatnump elm)
               (setf (aref a i) elm)
               (progn
                 (setq elm ($bfloat elm))
                 (if (not ($freeof '$%i elm))
                     (return-from $integer_relation nil))
                 (if (not ($bfloatp elm))
                     (merror "Non-bfloat element in argument to `integer_relation':~%~M.~%" elm))
                 (setf (aref a i) elm))))
         (setq l (cdr l)))
    (let ((ans (integer-relations a n)))
      (if ans
	  `((mlist simp) ,@ans)
          nil))))

(defmvar $pslq_precision nil)
(defmvar $pslq_treshold nil)
(defmvar $pslq_depth nil)
(defmvar $pslq_status 0)

(defmvar $pslq_fail_norm nil)

(defun mabs (x)
  (if (mlsp x 0) (m- x) x))

(defun nearest-integer (x)
  (let ((nx ($entier x)))
    (if (mlsp 0.5 (m- x nx))
	(1+ nx)
        nx)))

(defun integer-relations (x n)
  (let ((A (make-array `(,n ,n) :initial-element 0))
	(B (make-array `(,n ,n) :initial-element 0))
	(H (make-array `(,n ,(1- n)) :initial-element 0))
	(gamma (sqrt (/ 4 3)))
	(s (make-array `(,n) :initial-element 0))
	(y (make-array `(,n) :initial-element 0))
	($pslq_precision (if $pslq_precision $pslq_precision (power 10 (- $fpprec 2))))
	($pslq_treshold (if $pslq_treshold $pslq_treshold (power 10 (- 2 $fpprec))))
	($pslq_depth (if $pslq_depth $pslq_depth (* 20 n)))
	(tt))
    
    ;; Initialize A, B and s
    (loop for k from 0 to (1- n) do
         (setf (aref A k k) 1)
         (setf (aref B k k) 1)
         (loop for j from k to (1- n) do
              (setf (aref s k) (m+ (aref s k) (power (aref x j) 2))))
         (setf (aref s k) ($sqrt (aref s k))))
    (setf tt (aref s 0))
    
    ;; Initialize y, normalize s
    (loop for k from 0 to (1- n) do
         (setf (aref y k) (m// (aref x k) tt))
         (setf (aref s k) (m// (aref s k) tt)))
    
    ;; Initialize H
    (loop for i from 0 to (1- n) do
         (if (< i (- n 1))
             (setf (aref H i i) (m// (aref s (1+ i)) (aref s i))))
         (loop for j from 0 to (1- i) do
              (setf (aref H i j) (m- (m// (m* (aref y i) (aref y j))
                                          (m* (aref s j) (aref s (1+ j))))))))
    
    ;; Perform reduction on H, update A, B, y
    (loop for i from 1 to (- n 1) do
         (loop for j from (1- i) downto 0 do
              (setq tt (nearest-integer (m// (aref H i j) (aref H j j))))
              (setf (aref y j) (m+ (aref y j) (m* tt (aref y i))))
              (loop for k from 0 to j do
                   (setf (aref H i k) (m- (aref H i k) (m* tt (aref H j k)))))
              (loop for k from 0 to (1- n) do
                   (setf (aref A i k) (m- (aref A i k) (m* tt (aref A j k))))
                   (setf (aref B k j) (m+ (aref B k j) (m* tt (aref B k i)))))))
    
    (do ((r 1 (1+ r))) ((= r $pslq_depth))
      (let ((m 0) (mm 0) (s 1))
	
	;; Find maximal value in H
	(loop for i from 0 to (m- n 2) do
             (setq s (* gamma s))
             (if (mlsp mm (m* s (mabs (aref H i i))))
                 (progn
                   (setf m i)
                   (setf mm (m* (expt gamma i) (mabs (aref H i i)))))))
	
	;; Swap entries in y
	(rotatef (aref y m) (aref y (1+ m)))
	;; Swap rows in A and columns in B
	(loop for i from 0 to (- n 1) do
             (rotatef (aref A m i) (aref A (1+ m) i))
             (rotatef (aref B i m) (aref B i (1+ m))))
	;; Swap rows in H
	(loop for i from 0 to (- n 2) do
             (rotatef (aref H m i) (aref H (1+ m) i)))
	
	;; Update H
	(if (< m (- n 2))
	    (let* ((t0 ($sqrt (m+ (power (aref H m m) 2) (power (aref H m (1+ m)) 2))))
		   (t1 (m// (aref H m m) t0))
		   (t2 (m// (aref H m (1+ m)) t0))
		   (t3) (t4))
	      (loop for i from m to (1- n) do
                   (setq t3 (aref H i m))
                   (setq t4 (aref H i (1+ m)))
                   (setf (aref H i m) (m+ (m* t1 t3) (m* t2 t4)))
                   (setf (aref H i (1+ m)) (m- (m* t1 t4) (m* t2 t3))))))
	
	;; Block reduction on H
	(loop for i from (1+ m) to (1- n) do
             (loop for j from (min (1- i) (1+ m)) downto 0 do
                  (setq tt (nearest-integer (m// (aref H i j) (aref H j j))))
                  (setf (aref y j) (m+ (aref y j) (m* tt (aref y i))))
                  (loop for k from 0 to j do
                       (setf (aref H i k) (m- (aref H i k) (m* tt (aref H j k)))))
                  (loop for k from 0 to (1- n) do
                       (setf (aref A i k) (m- (aref A i k) (m* tt (aref A j k))))
                       (setf (aref B k j) (m+ (aref B k j) (m* tt (aref B k i)))))))
	
	;; Find the bound M
	(let ((maxNorm 0))
	  (loop for j from 0 to (1- n) do
               (let ((absHj 0))
                 (loop for i from 0 to (- n 2) do
                      (if (mlsp absHj (mabs (aref H j i)))
                          (setq absHj (aref H j i))))
                 (if (mlsp maxNorm absHj)
                     (setq maxNorm absHj))))
	  (setq $pslq_fail_norm (m// 1 maxNorm))
	  
	  ;; Check to see if we have a relation
	  (loop for j from 0 to (1- n) do
               (if (mlsp (mabs (aref y j)) $pslq_treshold)
                   (progn
                     (let ((ans ()))
                       (loop for i from 0 to (1- n) do
                            (setq ans (append ans `(,(aref B i j)))))
                       (setq $pslq_status 1)
                       (return-from integer-relations ans)))))
	  
	  ;; Check to see if we exsausted the precision
	  (loop for i from 0 to (1- n) do
               (loop for j from 0 to (1- n) do
                    (if (mlsp $pslq_precision (mabs (aref A i j)))
                        (progn
                          (setq $pslq_status 2)
                          (return-from integer-relations nil)))))
	  )))
    (setq $pslq_status 3)
    (return-from integer-relations nil) ))
