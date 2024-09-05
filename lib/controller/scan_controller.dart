import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as imageLib;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:get/get.dart';
import 'package:get/get_rx/src/rx_workers/utils/debouncer.dart';
import 'package:permission_handler/permission_handler.dart';
// import 'package:tflite_v2/tflite_v2.dart';
import 'package:flutter/services.dart'; // Import this for vibration
import 'package:vibration/vibration.dart';
import 'package:just_audio/just_audio.dart';

final player = AudioPlayer();

double root(num value, num rootDegree) {
  // Check dulu benar apa kagak
  if (rootDegree <= 0) {
    throw ArgumentError('Must positive');
  }
  return math.pow(value, 1 / rootDegree).toDouble();
}

class ScanController extends GetxController {
  // RxList<MapEntry<Map<String, double>, String>> boundingBoxes =
  //     <MapEntry<Map<String, double>, String>>[].obs;
  RxList<Uint8List> capturedImages = <Uint8List>[].obs;
  RxInt currentCameraIndex = 0.obs;
  RxString modelPath = 'assets/eepy_v16_float16.tflite'.obs;
  FlutterVision vision = FlutterVision();
  late CameraController cameraController;
  late List<CameraDescription> cameras;
  final _debouncer = Debouncer(delay: const Duration(milliseconds: 500));
  RxBool isCameraInit = false.obs;
  RxBool isLoaded = false.obs;
  RxInt cameraCount = 0.obs;
  RxDouble width = 0.0.obs;
  RxList<MapEntry<Map<String, double>, String>> boundingBoxes =
      <MapEntry<Map<String, double>, String>>[].obs;
  RxDouble height = 0.0.obs;
  RxDouble x1 = 0.0.obs;
  RxDouble x2 = 0.0.obs;
  RxDouble y1 = 0.0.obs;
  RxDouble y2 = 0.0.obs;
  RxString model = "".obs;
  RxString labels = "".obs;
  RxString rawlabel = "".obs;
  RxString name = "".obs;
  RxString diagnose = "".obs;
  RxString accuracy = "".obs;
  RxDouble camwidth = 0.0.obs;
  RxDouble camheight = 0.0.obs;
  int frameCount = 0;
  bool isDetecting = false;
  int frameDetect = 0;
  int mataTertutupFrameCount = 0;
  RxInt eyeDurationThreshold = 5.obs;
  var isDarkMode = false.obs;
  var showSlider = false.obs;
  int progress_activation = 0;
  bool isPlaying = false;

  void toggleDarkMode() {
    isDarkMode.value = !isDarkMode.value;
  }

  Future<void> changeModel(String newModelPath) async {
    try {
      // Unload the current model
      await vision.closeYoloModel();

      // Update the model path
      modelPath.value = newModelPath;

      // Load the new model
      await initTFLite();

      // Reinitialize the camera
      await cameraController.dispose();
      await initCamera();
    } catch (e) {
      print("Error changing model: $e");
    }
  }

  void captureFrame(
      CameraImage image, double left, double top, double right, double bottom) {
    try {
      int x1 = (left * image.width).round();
      int y1 = (top * image.height).round();
      int x2 = (right * image.width).round();
      int y2 = (bottom * image.height).round();

      final int width = x2 - x1;
      final int height = y2 - y1;

      final Uint8List yPlane = image.planes[0].bytes;
      final Uint8List uPlane = image.planes[1].bytes;
      final Uint8List vPlane = image.planes[2].bytes;

      final int yRowStride = image.planes[0].bytesPerRow;
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

      final imageLib.Image tempImage = imageLib.Image(width, height);

      for (int y = y1; y < y2; y++) {
        for (int x = x1; x < x2; x++) {
          final int uvIndex = uvPixelStride * ((x / 2).floor() - x1 ~/ 2) +
              uvRowStride * ((y / 2).floor() - y1 ~/ 2);
          final int yIndex = y * yRowStride + x;

          final int yp = yPlane[yIndex];
          final int up = uPlane[uvIndex];
          final int vp = vPlane[uvIndex];

          // Convert pixel from YUV to RGB
          int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
          int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
              .round()
              .clamp(0, 255);
          int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);

          // Set pixel color in image
          tempImage.setPixelRgba(x - x1, y - y1, r, g, b);
        }
      }

      // Encode image to PNG
      Uint8List png =
          Uint8List.fromList(imageLib.PngEncoder().encodeImage(tempImage));

      capturedImages.add(png);

      if (capturedImages.length > 2) {
        capturedImages.removeAt(0);
      }
    } catch (e) {
      print("Error capturing frame: $e");
    }
  }

  void switchCamera() async {
    currentCameraIndex.value = (currentCameraIndex.value + 1) % cameras.length;
    await cameraController.dispose();
    cameraController = CameraController(
      cameras[currentCameraIndex.value],
      ResolutionPreset.max,
      imageFormatGroup: ImageFormatGroup.yuv420,
      enableAudio: false,
    );
    await cameraController.initialize().then((value) {
      cameraController.startImageStream((image) {
        frameCount++;
        if (frameCount % 5 == 0 && !isDetecting) {
          frameCount = 0;
          objectDetector(image);
        }
        update();
        isCameraInit(true);
      });
    });
    update();
  }

  checkPermission(Permission permission, String classifies) async {
    final status = await permission.request();
    if (status.isGranted) {
      classify(classifies);
    } else {
      Get.snackbar("Eror", "Permission is not granted");
    }
  }

  classify(String classify) async {
    update();
    print("ini modelnya ${model.value}");
    print("ini labelnya ${labels.value}");
    await initTFLite();
    if (isCameraInit.isFalse) {
      initCamera();
    } else {
      cameraController.resumePreview();
    }
    toCamera();
  }

  initCamera() async {
    if (await Permission.camera.request().isGranted) {
      cameras = await availableCameras();

      final orientation = MediaQuery.of(Get.context!).orientation;

      ResolutionPreset resolutionPreset;
      if (orientation == Orientation.portrait) {
        resolutionPreset = ResolutionPreset.high;
      } else {
        resolutionPreset = ResolutionPreset.ultraHigh;
      }

      cameraController = CameraController(
        cameras[currentCameraIndex.value],
        resolutionPreset,
        imageFormatGroup: ImageFormatGroup.yuv420,
        enableAudio: false,
      );

      await cameraController.initialize().then((value) {
        cameraController.startImageStream((image) {
          frameCount++;
          if (frameCount % 5 == 0 && !isDetecting) {
            frameCount = 0;
            objectDetector(image);
          }
          update();
          isCameraInit(true);
        });
      });
      update();
    } else {
      print("permission denied");
    }
  }

  testOut() {
    print("ini berubah ${eyeDurationThreshold.value}");
  }

  objectDetector(CameraImage image) async {
    if (isDetecting) return;
    isDetecting = true;

    // Determine if the front camera is being used
    final isFrontCamera = cameras[currentCameraIndex.value].lensDirection ==
        CameraLensDirection.front;

    try {
      final detector = await vision.yoloOnFrame(
        bytesList: image.planes.map((plane) => plane.bytes).toList(),
        imageHeight: image.height,
        imageWidth: image.width,
        iouThreshold: 0.3,
        confThreshold: 0.3,
        classThreshold: 0.3,
      );

      boundingBoxes.clear(); // Clear the list before adding new bounding boxes

      bool mataTertutupDetected =
          false; // Flag to track if "Mata tertutup" is detected

      for (final detectedObject in detector) {
        final left = detectedObject['box'][0];
        final top = detectedObject['box'][1];
        final right = left + detectedObject['box'][2];
        final bottom = top + detectedObject['box'][3];
        final confidence = detectedObject['box'][4];
        final label = detectedObject['tag'];

        if (confidence > 0.3) {
          // Calculate bounding box coordinates
          double normalizedLeft = math.pow(left, 1.1) / image.width;
          double normalizedTop = root(top, 1.129) / image.height;
          double normalizedRight = math.pow(right, 1.01) / image.width;
          double normalizedBottom = root(bottom, 1.2) / image.height;

          // Adjust top and bottom coordinates if the label starts with "Mata" or "Mulut"
          if (label.startsWith("Mata") || label.startsWith("Mulut")) {
            normalizedTop -= 60 / image.height;
            normalizedBottom -= 60 / image.height;
          }

          // Invert left and right coordinates if using the front camera
          if (isFrontCamera) {
            normalizedRight = normalizedRight + 0.1;
            double tmpTop = normalizedTop;
            normalizedTop = 0.8 - normalizedBottom;
            normalizedBottom = 0.8 - tmpTop;
          }

          // Add bounding box and label to the list
          boundingBoxes.add(
            MapEntry(
              {
                'left': normalizedLeft,
                'top': normalizedTop,
                'right': normalizedRight,
                'bottom': normalizedBottom,
              },
              label,
            ),
          );

          if (label == "Mata tertutup") {
            mataTertutupDetected =
                true; // Set the flag if "Mata tertutup" is detected
          }
        }
      }

      print("Current Object detection $boundingBoxes");

      if (mataTertutupDetected) {
        mataTertutupFrameCount++;

        // Vibrate the phone if "Mata tertutup" is detected for more than 5 consecutive frames
        if (mataTertutupFrameCount > eyeDurationThreshold.value) {
          Vibration.vibrate(
              duration: 1000); // Vibrate the device for 1 second
          if (!isPlaying) {
            player.setLoopMode(LoopMode.one);
            player.setAsset('assets/warn.mp3');
            // Set the player to loop the audio// Set the audio file
            player.play(); // Start playing the warning sound
            isPlaying = true;
          }
        }
      } else {
        mataTertutupFrameCount =
            0; // Reset the counter if "Mata tertutup" is not detected
        player.stop(); // Stop the warning sound
        isPlaying = false;
      }
    
      update();
    } catch (e) {
      print("Error in object detection: $e");
    } finally {
      isDetecting = false;
    }
  }

  initTFLite() async {
    try {
      await vision.closeYoloModel();
      await vision.loadYoloModel(
          labels: 'assets/eepy_label.txt',
          modelPath: modelPath.value, // Use the modelPath value
          modelVersion: "yolov8",
          quantization: false,
          numThreads: 4,
          useGpu: true);
      isLoaded(true);
    } catch (e) {
      print(e);
    }
  }

  void closeTFLiteResources() {
    model.value = "";
    labels.value = "";
    isLoaded(false);
  }

  void disposeCamera() {
    cameraController.pausePreview();
    // isCameraInit(false);
  }

  toCamera() {
    Get.toNamed("/home");
  }

  toDashboard() {
    if (isCameraInit.isTrue && isLoaded.isTrue) {
      vision.closeYoloModel();
      closeTFLiteResources();
      disposeCamera();
      Get.toNamed("/dashboard");
    } else {
      Get.snackbar("Error", "Wait for a while");
    }
  }
}
