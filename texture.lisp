;;;; texture.lisp
;;;; Please see the licence.txt for the CLinch 

(in-package #:clinch)

(defclass texture (buffer)
  ((tex-id
    :accessor tex-id
    :initform nil
    :initarg :tex-id)
   (width
    :reader width
    :initform nil
    :initarg :width)
   (height
    :reader height
    :initform nil
    :initarg :height)
   (type
    :accessor qtype
    :initarg :qtype
    :initform :unsigned-byte)
   (data-format
    :accessor data-format
    :initform :bgra
    :initarg :format)
   (stride
    :reader Stride
    :initform 4
    :initarg :stride)
   (target
    :reader target
    :initform :pixel-unpack-buffer
    :initarg :target))
    (:documentation "Creates and keeps track of a texture object and its buffer (shared memory with gpu, sort of)."))



(defmethod initialize-instance :after ((this texture) &key
				       (format :bgra)
				       (wrap-s :repeat)
				       (wrap-t :repeat)
				       (mag-filter :linear)
				       (min-filter :linear))
    "Sets up a texture instance.
      type:   cffi type NOTE: use :unsigned-int if you are creating an index buffer.
      id:     OpenGL buffer id
      vcount: vertex count (or number of tuples if not using vertexes)
      stride: The number of values in each pixel.
      target: OpenGL buffer target. If you use this, think about subclassing. For more info lookup glBindBuffer().
      usage:  Tells OpenGL how often you wish to access the buffer. 
      loaded: Has data been put into the buffer. Buffers without data is just future storage, just be sure to set it before you use it.
      format: The OpenGL Format of the Color Data. blue-green-red-alpha is default and prefered for simplicity.
      wrap-s & wrap-t: Wrap texture vertical or horizontal.
      mag-filter & min-filter: Magnification an minimization method."

  
  (with-slots ((tex-id tex-id)
	       (w width)
	       (h height)
	       (this-target target)
	       (dtype type)) this
    
    (unless tex-id (setf tex-id (car (gl:gen-textures 1))))
    
    (gl:bind-texture :texture-2d (tex-id this))
    (gl:tex-parameter :texture-2d :texture-wrap-s wrap-s)
    (gl:tex-parameter :texture-2d :texture-wrap-t wrap-t)
    (gl:tex-parameter :texture-2d :texture-mag-filter mag-filter)
    (gl:tex-parameter :texture-2d :texture-min-filter min-filter)
    
    (when (loaded? this)
      (gl:tex-image-2d :texture-2d 0 :rgba w h 0 format
		       (cffi-type->gl-type dtype)
		       (cffi:null-pointer))
      tex-id)))
    
    

(defmethod bind ((this texture) &key )
  "Wrapper around glBindBuffer. Puts the texture into play."
  (gl:bind-buffer (target this) (id this))
  (gl:bind-texture :texture-2d (tex-id this)))

(defmethod map-buffer ((this texture) &optional (access :READ-WRITE))
  "Returns a pointer to the texture data. YOU MUST CALL UNMAP-BUFFER AFTER YOU ARE DONE!
   Access options are: :Read-Only, :Write-Only, and :READ-WRITE. NOTE: Using :read-write is slower than the others. If you can, use them instead."
  (bind this)
  (gl:map-buffer (target this) access))

(defmethod unmap-buffer ((this texture))
  "Release the pointer given by map-buffer. NOTE: THIS TAKES THE BUFFER OBJECT, NOT THE POINTER! ALSO, DON'T TRY TO RELASE THE POINTER."
  (gl:unmap-buffer (target this))
  (gl:bind-texture  :texture-2d (tex-id this))
  (gl:Tex-Image-2D :texture-2d 0 :rgba  (width this) (height this) 0 :bgra (cffi-type->gl-type (qtype this)) (cffi:null-pointer))
  
  (gl:bind-texture :texture-2d 0)
  (gl:bind-buffer (target this) 0))
	  
(defmethod bind-sampler ((this texture) shader name tex-unit)
  "Shaders pass information by using named values called Uniforms. Textures are passed using Samplers. This sets a texture to a sampler uniform" 
  (gl:active-texture (+ (cffi:foreign-enum-value '%gl:enum :texture0) tex-unit))
  (attach-uniform shader name tex-unit)
  (gl:bind-texture :texture-2d (tex-id this)))


(defmacro with-loaded-32bit-map ((path &key width height bitvar widthvar heightvar) &body body)
  "Loads a bitmap into memory using FreeImage.
     width: If you want a specific width, set this.
     height: If you want a specific height, set this.
     bitvar: The variable name for the mapped data pointer.
     widthvar: The variable name of the width (if width is set then equal to width)
     heightvar: The variable name of the height (if height is set then equal to height)

     body:    Your code."
  (let ((dib (gensym))
	(orig-w (if widthvar widthvar (gensym)))
	(orig-h (if heightvar heightvar (gensym)))
	(bits (if bitvar bitvar 'bits))
	(user-w (gensym))
	(user-h (gensym))
	(new-dib (gensym)))
    `(let* ((,user-w ,width)
	    (,user-h ,height)
	    (,dib (freeimage::get-32bit-dib ,path))
	    (,orig-w (freeimage:freeimage-getwidth ,dib))
	    (,orig-h (freeimage:freeimage-getheight ,dib))
	    (,bits))

       (if (or ,user-w ,user-h)
	   (let* ((new-dib (freeimage:freeimage-rescale ,dib ,user-w ,user-h)))
	     (freeimage:unload-dib ,dib)
	     (setf ,dib ,new-dib)
	     (setf ,orig-w ,user-w)
	     (setf ,orig-h ,user-h)))
       
       (setf ,bits (freeimage::freeimage-getbits ,dib))
       (freeimage:freeimage-flipvertical ,dib)
       ,@body

       (freeimage:unload-dib ,dib))))



(defmethod unload :after ((this texture) &key)
  (gl:delete-textures (list (tex-id this))))