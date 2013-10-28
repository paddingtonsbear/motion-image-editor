class Motion; class ImageEditorController < UIViewController
  attr_reader :touch_center, :scale_center, :scale, :output_width, :source_image, :crop_rect

  def viewDidLoad
    super

    add_subviews

    add_gesture_recognizers

    setup_constraints
  end

  def process_image
    view.userInteractionEnabled = false

    start_transform_callback.call

    # Async
    result_ref = old_transform_image(
      image_view.transform,
      source_image:       source_image.CGImage,
      source_size:        source_image.size,
      source_orientation: source_image.imageOrientation,
      output_width:       output_width || source_image.size.width,
      crop_rect:          crop_rect,
      image_view_size:    image_view.bounds.size)

    # Main

    transformed_image = UIImage.imageWithCGImage(
      result_ref,
      scale: 1.0,
      orientation: UIImageOrientationUp)

    CGImageRelease(result_ref)

    view.userInteractionEnabled = true

    done_callback.call(transformed_image)

    end_transform_callback.call
  end

  def crop_rect=(rect)
    @crop_rect = rect

    crop_view.crop_rect = rect
  end

  def transform_image(transform, source_image: source_image, source_size: source_size, source_orientation: source_orientation, output_width: output_width, crop_rect: crop_rect, image_view_size: image_view_size)

    aspect = crop_rect.size.height / crop_rect.size.width
    output_size = CGSizeMake(output_width, output_width * aspect)

    context = CGBitmapContextCreate(
      nil,                                      # data
      output_size.width,                        # width
      output_size.height,                       # height
      CGImageGetBitsPerComponent(source_image), # bits per component
      0,                                        # bytes per row
      CGImageGetColorSpace(source_image),       # color space
      CGImageGetBitmapInfo(source_image))       # bitmap info

    transform = CGAffineTransformIdentity
    transform = CGAffineTransformTranslate(transform, crop_rect.size.width / 2, crop_rect.size.height / 2)
    transform = CGAffineTransformScale(transform, 1.0, -1.0)

    CGContextConcatCTM(context, transform)

    CGContextDrawImage(context, CGRectMake(image_view_size.width / 2, -source_image.size.height/2, source_image.size.width, source_image.size.height), source_iamge.CGImage)

    rotated_image = UIImage.imageWithCGImage(CGBitmapContextCreateImage(context))
  end

  def old_transform_image(transform, source_image: source_image, source_size: source_size, source_orientation: source_orientation, output_width: output_width, crop_rect: crop_rect, image_view_size: image_view_size)
    aspect = crop_rect.size.height / crop_rect.size.width
    output_size = CGSizeMake(output_width, output_width * aspect)

    context = CGBitmapContextCreate(
      nil,                                      # data
      output_size.width,                        # width
      output_size.height,                       # height
      CGImageGetBitsPerComponent(source_image), # bits per component
      0,                                        # bytes per row
      CGImageGetColorSpace(source_image),       # color space
      CGImageGetBitmapInfo(source_image))       # bitmap info

    CGContextSetFillColorWithColor(context,  UIColor.clearColor.CGColor)
    CGContextFillRect(context, CGRectMake(0, 0, output_size.width, output_size.height))

    ui_coords = CGAffineTransformMakeScale(output_size.width / crop_rect.size.width,
                                           output_size.height / crop_rect.size.height)

    ui_coords = CGAffineTransformTranslate(ui_coords, crop_rect.size.width / 2.0,
                                           crop_rect.size.height / 2.0)

    ui_coords = CGAffineTransformScale(ui_coords, 1.0, -1.0)
    CGContextConcatCTM(context, ui_coords)

    CGContextConcatCTM(context, transform)
    CGContextScaleCTM(context, 1.0, -1.0)
    #CGContextConcatCTM(context, orientationTransform)

    drawing_rect = CGRectMake(-image_view_size.width / 2.0, -image_view_size.height / 2.0, image_view_size.width, image_view_size.height)

    CGContextDrawImage(context, drawing_rect, source_image)

    CGBitmapContextCreateImage(context)
  end

  def done_callback
    @done_callback ||= -> (image) { }
  end

  def cancel_callback
    @cancel_callback ||= -> { }
  end

  def start_transform_callback
    @start_transform_callback ||= -> { }
  end

  def end_transform_callback
    @end_transform_callback ||= -> { }
  end

  def viewDidAppear(animated)
    super

    reset
  end

  def add_subviews
    view.addSubview(crop_view)
    view.insertSubview(image_view, belowSubview: crop_view)
  end

  def add_gesture_recognizers
    crop_view.addGestureRecognizer(pan_recognizer)
    crop_view.addGestureRecognizer(pinch_recognizer)
    crop_view.addGestureRecognizer(rotation_recognizer)
    crop_view.addGestureRecognizer(tap_recognizer)
  end

  def reset
    @scale = 1

    image_view.transform = CGAffineTransformIdentity
    image_view.frame     = view.bounds
    image_view.transform = CGAffineTransformMakeScale(scale, scale)
  end

  def touchesBegan(touches, withEvent: event)
    handle_touches(event.allTouches)
  end

  def touchesMoved(touches, withEvent: event)
    handle_touches(event.allTouches)
  end

  def touchesEnded(touches, withEvent: event)
    handle_touches(event.allTouches)
  end

  def touchesCancelled(touches, withEvent: event)
    handle_touches(event.allTouches)
  end

  def handle_touches(touches)
    @touch_center = CGPointZero

    if touches.count >= 2
      touches.each do |touch|
        touch_location = touch.locationInView(image_view)

        @touch_center = CGPointMake(touch_center.x + touch_location.x, touch_center.y + touch_location.y)
      end

      @touch_center = CGPointMake(touch_center.x / touches.count, touch_center.y / touches.count)
    end
  end

  def handle_pan(recognizer)

    translation = recognizer.translationInView(image_view)
    transform   = CGAffineTransformTranslate(image_view.transform, translation.x, translation.y)

    image_view.transform = transform

    recognizer.setTranslation(CGPointZero, inView: crop_view)
  end

  def handle_pinch(recognizer)
    if recognizer.state == UIGestureRecognizerStateBegan
      @scale_center = @touch_center
    end

    delta_x = scale_center.x - image_view.bounds.size.width / 2.0
    delta_y = scale_center.y - image_view.bounds.size.height / 2.0

    transform = CGAffineTransformTranslate(image_view.transform, delta_x, delta_y)
    transform = CGAffineTransformScale(transform, recognizer.scale, recognizer.scale)
    transform = CGAffineTransformTranslate(transform, -delta_x, -delta_y)

    @scale *= recognizer.scale

    @image_view.transform = transform

    recognizer.scale = 1
  end

  def handle_rotation(recognizer)

    delta_x = touch_center.x - image_view.bounds.size.width / 2
    delta_y = touch_center.y - image_view.bounds.size.height / 2

    transform = CGAffineTransformTranslate(image_view.transform, delta_x, delta_y)
    transform = CGAffineTransformRotate(transform, recognizer.rotation)
    transform = CGAffineTransformTranslate(transform, -delta_x, -delta_y)

    image_view.transform = transform

    recognizer.rotation = 0
  end

  def handle_tap(recognizer)
    reset
  end

  def pan_recognizer
    @pan_recognizer ||= UIPanGestureRecognizer.alloc.initWithTarget(self, action: 'handle_pan:').tap do |recognizer|
      recognizer.cancelsTouchesInView = false
      recognizer.delegate             = self
    end
  end

  def tap_recognizer
    @tap_recognizer ||= UITapGestureRecognizer.alloc.initWithTarget(self, action: 'handle_tap:').tap do |recognizer|
      recognizer.numberOfTapsRequired = 2
    end
  end

  def rotation_recognizer
    @rotation_recognizer ||= UIRotationGestureRecognizer.alloc.initWithTarget(self, action: 'handle_rotation:').tap do |recognizer|
      recognizer.cancelsTouchesInView = false
      recognizer.delegate             = self
    end
  end

  def pinch_recognizer
    @pinch_recognizer ||= UIPinchGestureRecognizer.alloc.initWithTarget(self, action: 'handle_pinch:').tap do |recognizer|
      recognizer.cancelsTouchesInView = false
      recognizer.delegate             = self
    end
  end

  def source_image=(image)
    @source_image = image

    image_view.image = image
  end

  def setup_constraints
    view.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat(
      'H:|[crop]|',
      options: 0,
      metrics: nil,
      views:   { 'crop' => crop_view }))

    view.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat(
      'V:|[crop]|',
      options: 0,
      metrics: nil,
      views:   { 'crop' => crop_view }))
  end

  def image_view
    @image_view ||= UIImageView.alloc.init.tap do |view|
      view.translatesAutoresizingMaskIntoConstraints = false
    end
  end

  def crop_view
    @crop_view ||= Motion::ImageEditorView.alloc.init.tap do |view|
      view.translatesAutoresizingMaskIntoConstraints = false
    end
  end

  def prefersStatusBarHidden
    true
  end
end; end
