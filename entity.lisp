;;;; entity.lisp
;;;; Please see the licence.txt for the CLinch 

(in-package #:clinch)

(defclass entity ()
  ((shader
    :initform nil
    :initarg :shader
    :reader shader)
   (indexes
    :initform nil
    :initarg :indexes
    :reader indexes)
   (render-values
    :initform nil
    :initarg :values
    :reader render-values)))


(defmethod initialize-instance :after ((this entity) &key (compile t) parent (strict-index nil))
  "Strict-index: ALL-INDICES-USED? on THIS"
  (when parent (add-child parent this)))

(defmethod (setf shader) (new-value (this entity))
  (sdl2:in-main-thread ()
    (setf (slot-value this 'shader) new-value)))

(defmethod (setf indexes) (new-value (this entity))
  (sdl2:in-main-thread ()
    (setf (slot-value this 'indexes) new-value)))

(defmethod (setf render-values) (new-value (this entity))
  (sdl2:in-main-thread ()
    (setf (slot-value this 'render-values) new-value)))
		       
(defun render-value-location (values key)
  (loop
     for i in values 
     for x from 0
     if (equal key (second i))
     do (return x)))

(defun assoc-on-second (item lst) 
  (or (when (equal item (cadar lst))
	(car lst))
      (assoc-on-second item (cdr lst))))

(defmethod render-value ((this entity) name)
  (third 
   (assoc-on-second name (clinch::render-values this))))

(defmethod (setf render-value) (new-value (this entity) name)
  (let ((ret
	 (with-accessors ((lst render-values)) this
	   (let ((loc (render-value-location lst name)))
	     (if loc
		 (sdl2:in-main-thread ()
		 (setf (third (nth loc lst)) new-value)))))))
    ret))

(defmethod get-primitive ((this entity) name)
  (let* ((buff      (get-render-value this name))
	 (stride    (stride buff))
	 (icount    (vertex-count (indexes this)))
	 (itype     (qtype (indexes this)))
	 (btype     (clinch:qtype buff))
	 (iret      (make-array (/ icount 3)))
	 (bret      (make-array (/ icount 3))))

    (clinch:with-mapped-buffer (iptr (indexes this) :read-only)
      (clinch:with-mapped-buffer (bptr buff :read-only)
	
	(dotimes (i (/ icount 3))
	  (let ((iarr1 (make-array 3 :element-type 'integer))
		(barr1 (make-array 3)))
	    
	    (dotimes (j 3)
	      (setf (elt iarr1 j) (cffi:mem-aref iptr itype (+ (* i 3) j)))

	      (let ((barr2 (make-array stride :element-type 'single-float)))
		(dotimes (k stride)
		  (setf (elt barr2 k)
			(cffi:mem-aref bptr btype (+ k (* (elt iarr1 j) stride)))))

		(setf (elt barr1 j) barr2)))
	    
	    (setf (elt iret i) iarr1)
	    (setf (elt bret i) barr1)))))

    (values bret iret)))


(defmethod triangle-intersection? ((this entity) start dir &key (vertex-name :vertices))
  (labels ((rec (primitives i distance u v index)
	     (multiple-value-bind (new-distance new-u new-v)
		 
		 (ray-triangle-intersect? start dir (first (car primitives)) (second (car primitives)) (third (car primitives)))
	       (when (and new-distance
			  (or (null distance)
			      (< new-distance distance)))
		 (setf distance new-distance
		       u new-u
		       v new-v
		       index i)))
	     (if (cdr primitives)
		 (rec (cdr primitives) (1+ i) distance u v index)
		 (values distance u v index))))
    (rec (get-primitive this vertex-name) 0 nil nil nil nil)))



(defmethod draw ((this entity) &key parent projection)
  (gl:matrix-mode :modelview)
  
  (with-accessors ((shader shader)) this
    (when shader 
      (let ((current-shader (if (typep shader 'function)
				(funcall shader)
				shader)))
	(use-shader current-shader)

	(if (vertices this)
	    (bind-buffer-to-vertex-array (vertices this))
	    (unbind-vertex-array))
	
	(if (normals this)
	    (bind-buffer-to-normal-array (normals this))
	    (unbind-normal-array))
	
	(loop
	   with tex-unit = 0
	   for (atr-or-uni name value) in (render-values this)
	   if (typep value 'function) do (setf value (funcall value))
	   collect (progn
		     ;;(format t "name: ~A value: ~A~%" name value)
		     (cond ((and (eql atr-or-uni :uniform)
				 (typep value 'texture)) (prog1 (bind-sampler value current-shader name tex-unit) (incf tex-unit)))
			   ((eql atr-or-uni :uniform)
			    
			    (attach-uniform current-shader name (cond ((eql value :projection) projection)
								      ((eql value :Model)      (or parent (sb-cga:identity-matrix)))
								      ((eql value :model-1) (typecase parent
											      (node (sb-cga:inverse-matrix
												     (current-transform parent)))
											      (array (sb-cga:inverse-matrix parent))
											      (t (sb-cga:identity-matrix))))
								      ((eql value :projection-1) (sb-cga:inverse-matrix projection))
								      ((eql value :normal) (typecase parent
											     (node
											      (convert-matrix4-to-matrix3
											       (sb-cga:transpose-matrix
												(sb-cga:inverse-matrix
												 (current-transform parent)))))
											     (array (convert-matrix4-to-matrix3
												     (sb-cga:transpose-matrix
												      (sb-cga:inverse-matrix parent))))
											     (t (make-identity-matrix3))))
								      (t value))))
			   
			   ((and (eql atr-or-uni :attribute)
				 (typep value 'buffer)) 
			    (bind-buffer-to-attribute-array value current-shader name))
			   ((eql atr-or-uni :attribute) (if (atom value)
							    (bind-static-values-to-attribute current-shader name value)
							    (bind-static-values-to-attribute current-shader name value)))))))))

  
  (draw-with-index-buffer (indexes this)))

(defmethod update ((this entity) &key parent matrix force)
  )

(defmethod render ((this entity) &key parent projection)

  (draw this :parent parent :projection projection))

(defmethod ray-entity-intersect? ((this clinch:entity) transform start end &optional (primitive :vertices))

  (multiple-value-bind (points index) (clinch::get-primitive this primitive)
    (let ((transformed-points (map 'list (lambda (x)
					   (map 'list (lambda (p) 
							(clinch:transform-point p transform)) x)) points)))
      (loop
	 with dist 
	 with u 
	 with v
	 with point
	 with point-number
	 for p from 0 to (1- (length transformed-points))
	 do (let ((pseq (elt transformed-points p)))
	      (multiple-value-bind (new-dist new-u new-v)
		  (clinch::ray-triangle-intersect? start end (elt pseq 0) (elt pseq 1) (elt pseq 2))
		
		(when (and new-dist
			   (or (null dist)
			       (> dist new-dist)))
		  (setf dist         new-dist
			u            new-u
			v            new-v
			point-number p)
		  (when index
		    (setf point (elt index p))))))
	 finally (return (when dist (values dist u v point point-number)))))))

(defmethod unload ((this entity) &key)
  "Release entity resources."
  )

(defmacro entity (&body rest)

  `(make-instance 'entity ,@rest :parent *parent*))

