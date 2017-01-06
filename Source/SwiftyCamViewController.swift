/*Copyright (c) 2016, Andrew Walz.
 
 Redistribution and use in source and binary forms, with or without modification,are permitted provided that the following conditions are met:
 
 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 
 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS
 BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
 GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */


import UIKit
import AVFoundation

// MARK: View Controller Declaration

open class SwiftyCamViewController: UIViewController {
    
    // MARK: Enumeration Declaration
    
    
    // Possible Camera Selection Posibilities

   public enum CameraSelection {
        case rear
        case front
    }
    
    // Used for Setting Video Quality of Capture Session
    // Corresponds to the AVCaptureSessionPreset String
    // Global Variables Declared in AVFoundation
    // AVCaptureSessionPresetPhoto is not supported as it does not support video capture
    // AVCaptureSessionPreset320x240 is not supported as it is the incorrect aspect ratio
    
    public enum VideoQuality {
        case high                  // AVCaptureSessionPresetHigh
        case medium                // AVCaptureSessionPresetMedium
        case low                   // AVCaptureSessionPresetLow
        case resolution352x288     // AVCaptureSessionPreset352x288
        case resolution640x480     // AVCaptureSessionPreset640x480
        case resolution1280x720    // AVCaptureSessionPreset1280x720
        case resolution1920x1080   // AVCaptureSessionPreset1920x1080
        case resolution3840x2160   // AVCaptureSessionPreset3840x2160
        case iframe960x540         // AVCaptureSessionPresetiFrame960x540
        case iframe1280x720        // AVCaptureSessionPresetiFrame1280x720
    }
    
    // Result from the AVCaptureSession Setup
    
    fileprivate enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    // MARK: Public Variable Declarations
    
    // Public Camera Delegate for the Custom View Controller Subclass
    
    public var cameraDelegate: SwiftyCamViewControllerDelegate?
    
    // Used to set the maximum duration of the video capture
    // Only used for SwiftyCamButton
    // Value of 0.0  does not enforce a fixed duration
    
    public var kMaximumVideoDuration : Double     = 0.0
    
    // Quality of rear facing camera
    // Quality of front caing quality will always be VideoQuality.high
    
    public var videoQuality : VideoQuality       = .high
    
    // Sets whether Pinch to Zoom is supported for the capture session
    // Pinch to zoom not supported on front facing camera
    
    public var pinchToZoom                       = true
    
    // Sets whether Tap to Focus is supported for the capture session
    // Tap to Focus is not supported on front facing camera
    // Tapping the capture session will call the SwiftyCamViewControllerDelegate delegate function SwiftyCamDidFocusAtPoint(focusPoint: CGPoint)
    
    public var tapToFocus                        = true
    
    // Sets whether SwiftyCam will prompt a user to the App Settings Screen if Camera or Microphone access is not authorized
    // If set to false and Camera/Microphone is not authorized, SwiftyCamViewControllerDelegate delegate
    // function SwiftyCamDidFailCameraPermissionSettings() will be called
    
    public var promptToAppPrivacySettings        = true
    
    
    // MARK: Public Get-only Variable Declarations
    
    // Returns a boolean if the torch (flash) is currently enabled
    
    private(set) public var isCameraFlashOn      = false
    
    // Returns a boolean if video is currently being recorded
    
    private(set) public var isVideRecording      = false
    
    // Returns a boolean if the capture session is currently running
    
    private(set) public var isSessionRunning     = false
    
    // Returns a CameraSelection enum for the currently utilized camera
    
    private(set) public var currentCamera        = CameraSelection.rear
    
    // MARK: Private Constant Declarations
    
    // Current Capture Session
    
    fileprivate let session                      = AVCaptureSession()
    
    // Serial queue used for setting up session
    
    fileprivate let sessionQueue                 = DispatchQueue(label: "session queue", attributes: [])
    
    // MARK: Private Variable Declarations
    
    // Variable for storing current zoom scale
    
    fileprivate var zoomScale                    = CGFloat(1.0)
    
    // Variable for storing initial zoom scale before Pinch to Zoom begins
    
    fileprivate var beginZoomScale               = CGFloat(1.0)
    
    // Variable for storing result of Capture Session setup
    
    fileprivate var setupResult                  = SessionSetupResult.success
    
    // BackgroundID variable for video recording
    
    fileprivate var backgroundRecordingID        : UIBackgroundTaskIdentifier? = nil
    
    // Video Input variable
    
    fileprivate var videoDeviceInput             : AVCaptureDeviceInput!
    
    // Movie File Output variable
    
    fileprivate var movieFileOutput              : AVCaptureMovieFileOutput?
    
    // Photo File Output variable
    
    fileprivate var photoFileOutput              : AVCaptureStillImageOutput?
    
    // Video Device variable
    
    fileprivate var videoDevice                  : AVCaptureDevice?
    
    // PreviewView for the capture session
    
    fileprivate var previewLayer                 : PreviewView!
    
    // Disable view autorotation for forced portrait recorindg
    
    open override var shouldAutorotate: Bool {
        return false
    }
    
    // MARK: ViewDidLoad

    override open func viewDidLoad() {
        super.viewDidLoad()
        previewLayer = PreviewView(frame: self.view.frame)
        
        // Add Pinch Gesture Recognizer for pinch to zoom
        
        addGestureRecognizers(toView: previewLayer)
        self.view.addSubview(previewLayer)
        previewLayer.session = session
        
        // Test authorization status for Camera and Micophone
        
        switch AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo){
            case .authorized:
                
                // already authorized
                break
            case .notDetermined:
                
                // not yet determined
                sessionQueue.suspend()
                AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: { [unowned self] granted in
                    if !granted {
                        self.setupResult = .notAuthorized
                    }
                    self.sessionQueue.resume()
                    })
            default:
                
                // already been asked. Denied access
                setupResult = .notAuthorized
            }
            sessionQueue.async { [unowned self] in
                self.configureSession()
        }
    }
    
    // MARK: ViewDidAppear
    
    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        sessionQueue.async {
            switch self.setupResult {
                case .success:
                    // Begin Session
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                case .notAuthorized:
                    // Prompt to App Settings
                    self.promptToAppSettings()
                case .configurationFailed:
                    // Unknown Error
                    DispatchQueue.main.async(execute: { [unowned self] in
                        let message = NSLocalizedString("Unable to capture media", comment: "Alert message when something goes wrong during capture session configuration")
                        let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                        alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
                        self.present(alertController, animated: true, completion: nil)
                })
            }
        }
    }
    
    // MARK: ViewDidDisappear
    
    override open func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        // If session is running, stop the session
        if self.isSessionRunning == true {
            self.session.stopRunning()
            self.isSessionRunning = false
        }
        
        //Disble flash if it is currently enables
        disableFlash()
    }
    
    // MARK: Public Functions
    
    // Capture photo from session
    
    public func takePhoto() {
        if let videoConnection = photoFileOutput?.connection(withMediaType: AVMediaTypeVideo) {
            videoConnection.videoOrientation = AVCaptureVideoOrientation.portrait
            photoFileOutput?.captureStillImageAsynchronously(from: videoConnection, completionHandler: {(sampleBuffer, error) in
                if (sampleBuffer != nil) {
                    let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sampleBuffer)
                    let image = self.processPhoto(imageData!)
                    
                    // Call delegate and return new image
                    self.cameraDelegate?.SwiftyCamDidTakePhoto(image)
                }
            })
        }
    }
    
    // Begin recording video
    
    public func startVideoRecording() {
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }
        
        let videoPreviewLayerOrientation = previewLayer!.videoPreviewLayer.connection.videoOrientation
        
        sessionQueue.async { [unowned self] in
            if !movieFileOutput.isRecording {
                if UIDevice.current.isMultitaskingSupported {
                    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }
                
                // Update the orientation on the movie file output video connection before starting recording.
                let movieFileOutputConnection = self.movieFileOutput?.connection(withMediaType: AVMediaTypeVideo)
                
                
                //flip video output if front facing camera is selected
                if self.currentCamera == .front {
                    movieFileOutputConnection?.isVideoMirrored = true
                }
                movieFileOutputConnection?.videoOrientation = videoPreviewLayerOrientation
                
                // Start recording to a temporary file.
                let outputFileName = UUID().uuidString
                let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
                movieFileOutput.startRecording(toOutputFileURL: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
                self.isVideRecording = true
                self.cameraDelegate?.SwiftyCamDidBeginRecordingVideo()
            }
            else {
                movieFileOutput.stopRecording()
            }
        }
    }
    
    // Stop video recording
    
    public func endVideoRecording() {
        if self.movieFileOutput?.isRecording == true {
            self.isVideRecording = false
            movieFileOutput!.stopRecording()
            self.cameraDelegate?.SwiftyCamDidFinishRecordingVideo()
        }
    }
    
    // Switch between front and rear camera
    
    public func switchCamera() {
        guard isVideRecording != true else {
            //TODO: Look into switching camera during video recording
            print("[SwiftyCam]: Switching between cameras while recording video is not supported")
            return
        }
        switch currentCamera {
        case .front:
            currentCamera = .rear
        case .rear:
            currentCamera = .front
        }
        
        self.session.stopRunning()

        sessionQueue.async { [unowned self] in
            
            // remove and re-add inputs and outputs
            
            for input in self.session.inputs {
                self.session.removeInput(input as! AVCaptureInput)
            }
            for output in self.session.outputs {
                self.session.removeOutput(output as! AVCaptureOutput)
            }
            
            self.configureSession()
            self.cameraDelegate?.SwiftyCamDidSwitchCameras(camera: self.currentCamera)
            self.session.startRunning()
        }
        
        // If flash is enabled, disable it as flash is not supported or needed for front facing camera
        disableFlash()
    }
    
    public func toggleFlash() {
        guard self.currentCamera == .rear else {
            // Flash is not supported for front facing camera
            return
        }
        
        let device = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
        // Check if device has a flash
        if (device?.hasTorch)! {
            do {
                try device?.lockForConfiguration()
                if (device?.torchMode == AVCaptureTorchMode.on) {
                    device?.torchMode = AVCaptureTorchMode.off
                    self.isCameraFlashOn = false
                } else {
                    do {
                        try device?.setTorchModeOnWithLevel(1.0)
                        self.isCameraFlashOn = true
                    } catch {
                        print("[SwiftyCam]: \(error)")
                    }
                }
                device?.unlockForConfiguration()
            } catch {
                print("[SwiftyCam]: \(error)")
            }
        }
    }
    
    // Override Touches Began
    // Used for Tap to Focus
    
    override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tapToFocus == true, currentCamera ==  .rear  else {
            // Ignore taps
            return
        }
        
        let screenSize = previewLayer!.bounds.size
        if let touchPoint = touches.first {
            let x = touchPoint.location(in: previewLayer!).y / screenSize.height
            let y = 1.0 - touchPoint.location(in: previewLayer!).x / screenSize.width
            let focusPoint = CGPoint(x: x, y: y)
            
            if let device = videoDevice {
                do {
                    try device.lockForConfiguration()
                    
                    device.focusPointOfInterest = focusPoint
                    device.focusMode = .autoFocus
                    device.exposurePointOfInterest = focusPoint
                    device.exposureMode = AVCaptureExposureMode.continuousAutoExposure
                    device.unlockForConfiguration()
                    //Call delegate function and pass in the location of the touch
                    self.cameraDelegate?.SwiftyCamDidFocusAtPoint(focusPoint: touchPoint.location(in: previewLayer))
                }
                catch {
                // just ignore
                }
            }
        }
    }
    
    // MARK: Private Functions
    
    // Configure session, add inputs and outputs

    fileprivate func configureSession() {
        guard setupResult == .success else {
            return
        }
        session.beginConfiguration()
        configureVideoPreset()
        addVideoInput()
        addAudioInput()
        configureVideoOutput()
        configurePhotoOutput()
        
        session.commitConfiguration()
    }
    
    // Configure preset
    // Front facing camera will always be set to VideoQuality.high
    // If set video quality is not supported, videoQuality variable will be set to VideoQuality.high
    
    fileprivate func configureVideoPreset() {
        
        if currentCamera == .front {
            session.sessionPreset = videoInputPresetFromVideoQuality(quality: .high)
        } else {
            if session.canSetSessionPreset(videoInputPresetFromVideoQuality(quality: videoQuality)) {
                session.sessionPreset = videoInputPresetFromVideoQuality(quality: videoQuality)
            } else {
                session.sessionPreset = videoInputPresetFromVideoQuality(quality: .high)
            }
        }
    }
    
    // Add Video Inputs
    
    fileprivate func addVideoInput() {
        switch currentCamera {
        case .front:
            videoDevice = SwiftyCamViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: .front)
        case .rear:
            videoDevice = SwiftyCamViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: .back)
        }
        
        if let device = videoDevice {
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                    if device.isSmoothAutoFocusSupported {
                        device.isSmoothAutoFocusEnabled = true
                    }
                }
                
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                
                device.unlockForConfiguration()
            } catch {
                print("[SwiftyCam]: Error locking configuration")
            }
        }
        
        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
            } else {
                print("[SwiftyCam]: Could not add video device input to the session")
                print(session.canSetSessionPreset(videoInputPresetFromVideoQuality(quality: videoQuality)))
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("[SwiftyCam]: Could not create video device input: \(error)")
            setupResult = .configurationFailed
            return
        }
    }
    
    // Add Audio Inputs
    
    fileprivate func addAudioInput() {
        do {
            let audioDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeAudio)
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
            
            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
            }
            else {
                print("[SwiftyCam]: Could not add audio device input to the session")
            }
        }
        catch {
            print("[SwiftyCam]: Could not create audio device input: \(error)")
        }
    }
    
    // Configure Movie Output
    
    fileprivate func configureVideoOutput() {
        let movieFileOutput = AVCaptureMovieFileOutput()
        
        if self.session.canAddOutput(movieFileOutput) {
            self.session.addOutput(movieFileOutput)
            if let connection = movieFileOutput.connection(withMediaType: AVMediaTypeVideo) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
            self.movieFileOutput = movieFileOutput
        }
    }
    
    // Configure Photo Output
    
    fileprivate func configurePhotoOutput() {
        let photoFileOutput = AVCaptureStillImageOutput()
        
        if self.session.canAddOutput(photoFileOutput) {
            photoFileOutput.outputSettings  = [AVVideoCodecKey: AVVideoCodecJPEG]
            self.session.addOutput(photoFileOutput)
            self.photoFileOutput = photoFileOutput
        }
    }
    
    // Get Image from Image Data
    
    fileprivate func processPhoto(_ imageData: Data) -> UIImage {
        let dataProvider = CGDataProvider(data: imageData as CFData)
        let cgImageRef = CGImage(jpegDataProviderSource: dataProvider!, decode: nil, shouldInterpolate: true, intent: CGColorRenderingIntent.defaultIntent)
        
        var image: UIImage!
        
        // Set proper orientation for photo
        // If camera is currently set to front camera, flip image
        
        switch self.currentCamera {
            case .front:
                image = UIImage(cgImage: cgImageRef!, scale: 1.0, orientation: .leftMirrored)
            case .rear:
                image = UIImage(cgImage: cgImageRef!, scale: 1.0, orientation: .right)
        }
        return image
    }
    
    // Handle zoom gesture
    
    @objc fileprivate func zoomGesture(pinch: UIPinchGestureRecognizer) {
        guard pinchToZoom == true else {
            //ignore pinch if pinchToZoom is set to false
            return
        }
            do {
                let captureDevice = AVCaptureDevice.devices().first as? AVCaptureDevice
                try captureDevice?.lockForConfiguration()
            
                zoomScale = max(1.0, min(beginZoomScale * pinch.scale,  captureDevice!.activeFormat.videoMaxZoomFactor))
            
                captureDevice?.videoZoomFactor = zoomScale
                
                // Call Delegate function with current zoom scale
                self.cameraDelegate?.SwiftyCamDidChangeZoomLevel(zoomLevel: zoomScale)
            
                captureDevice?.unlockForConfiguration()
            
            } catch {
                print("[SwiftyCam]: Error locking configuration")
        }
    }
    
    // Add pinch Gesture
    
    fileprivate func addGestureRecognizers(toView: UIView) {
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(zoomGesture(pinch:)))
        pinchGesture.delegate = self
        toView.addGestureRecognizer(pinchGesture)
    }
    
    //Handle Denied App Privacy Settings
    
    fileprivate func promptToAppSettings() {
        guard promptToAppPrivacySettings == true else {
            // Do not prompt user
            // Ca// delegate function SwiftyCamDidFailCameraPermissionSettings()
            self.cameraDelegate?.SwiftyCamDidFailCameraPermissionSettings()
            return
        }
        
        // prompt User with UIAlertView

        DispatchQueue.main.async(execute: { [unowned self] in
            let message = NSLocalizedString("AVCam doesn't have permission to use the camera, please change privacy settings", comment: "Alert message when the user has denied access to the camera")
            let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: .default, handler: { action in
                if #available(iOS 10.0, *) {
                        UIApplication.shared.openURL(URL(string: UIApplicationOpenSettingsURLString)!)
                } else {
                    if let appSettings = URL(string: UIApplicationOpenSettingsURLString) {
                            UIApplication.shared.openURL(appSettings)
                    }
                }
            }))
            self.present(alertController, animated: true, completion: nil)
        })
    }
    
    // Set AVCapturePreset from VideoQuality enum
    
    fileprivate func videoInputPresetFromVideoQuality(quality: VideoQuality) -> String {
        switch quality {
            case .high: return AVCaptureSessionPresetHigh
            case .medium: return AVCaptureSessionPresetMedium
            case .low: return AVCaptureSessionPresetLow
            case .resolution352x288: return AVCaptureSessionPreset352x288
            case .resolution640x480: return AVCaptureSessionPreset640x480
            case .resolution1280x720: return AVCaptureSessionPreset1280x720
            case .resolution1920x1080: return AVCaptureSessionPreset1920x1080
            case .iframe960x540: return AVCaptureSessionPresetiFrame960x540
            case .iframe1280x720: return AVCaptureSessionPresetiFrame1280x720
            case .resolution3840x2160:
                if #available(iOS 9.0, *) {
                    return AVCaptureSessionPreset3840x2160
                }
                else {
                    print("[SwiftyCam]: Resolution 3840x2160 not supported")
                    return AVCaptureSessionPresetHigh
                }
        }
    }
    
    fileprivate class func deviceWithMediaType(_ mediaType: String, preferringPosition position: AVCaptureDevicePosition) -> AVCaptureDevice? {
        if let devices = AVCaptureDevice.devices(withMediaType: mediaType) as? [AVCaptureDevice] {
            return devices.filter({ $0.position == position }).first
        }
        return nil
    }
    
    // Enable flash
    
    fileprivate func enableFlash() {
        if self.isCameraFlashOn == false {
            toggleFlash()
        }
    }
    
    // Disable flash
    
    fileprivate func disableFlash() {
        if self.isCameraFlashOn == true {
            toggleFlash()
        }
    }
}

extension SwiftyCamViewController : SwiftyCamButtonDelegate {
    
    // Sets the maximum duration of the SwiftyCamButton
    // Value of 0.0 will not enforce any maximum
    
    public func setMaxiumVideoDuration() -> Double {
        return kMaximumVideoDuration
    }
    
    // Set UITapGesture to take photo
    
    public func buttonWasTapped() {
        takePhoto()
    }
    
    // set UILongPressGesture start to begin video
    
    public func buttonDidBeginLongPress() {
        startVideoRecording()
    }
    
    // set UILongPressGesture begin to begin end video

    
    public func buttonDidEndLongPress() {
        endVideoRecording()
    }
    
    // Called if maximum duration is reached
    
    public func longPressDidReachMaximumDuration() {
        endVideoRecording()
    }
}

// MARK: AVCaptureFileOutputRecordingDelegate

extension SwiftyCamViewController : AVCaptureFileOutputRecordingDelegate {
    
    public func capture(_ captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAt outputFileURL: URL!, fromConnections connections: [Any]!, error: Error!) {
        if let currentBackgroundRecordingID = backgroundRecordingID {
            backgroundRecordingID = UIBackgroundTaskInvalid
            
            if currentBackgroundRecordingID != UIBackgroundTaskInvalid {
                UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
            }
        }
        if error != nil {
            print("[SwiftyCam]: Movie file finishing error: \(error)")
        } else {
            //Call delegate function with the URL of the outputfile
            self.cameraDelegate?.SwiftyCamDidFinishProcessingVideoAt(outputFileURL)
        }
    }
}

// MARK: UIGestureRecognizerDelegate

extension SwiftyCamViewController : UIGestureRecognizerDelegate {
    
    // Set beginZoomScale when pinch begins
    
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer.isKind(of: UIPinchGestureRecognizer.self) {
            beginZoomScale = zoomScale;
        }
        return true
    }
}



