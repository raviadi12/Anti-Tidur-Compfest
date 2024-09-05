lib\controller\scan_controller.dart

```dart
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

```

lib\main.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:simpleapp/route.dart';
import 'package:wakelock/wakelock.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Permission.camera.request();
  Wakelock.enable(); // Enable the wakelock to keep the screen on
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      getPages: AppRoutes.pages,
      initialRoute: "/dashboard",
    );
  }
}

```

lib\route.dart

```dart
import 'package:get/get.dart';
import 'package:simpleapp/controller/scan_controller.dart';
import 'package:simpleapp/view/camera_view.dart';
import 'package:simpleapp/view/dashboard.dart';
import 'package:simpleapp/view/sleep.dart'; // Import the SleepSound widget
import 'package:simpleapp/view/snore.dart'; // Import the SnoreScreen widget
import 'package:simpleapp/view/config.dart';

class AppRoutes {
  static final pages = [
    GetPage(
      transition: Transition.fadeIn,
      transitionDuration: const Duration(seconds: 2),
      name: '/home',
      page: () => const CameraView(),
    ),
    GetPage(
      transition: Transition.fadeIn,
      transitionDuration: const Duration(seconds: 2),
      name: '/config',
      page: () => const ConfigPage(),
    ),
    GetPage(
      transition: Transition.fadeIn,
      transitionDuration: const Duration(seconds: 2),
      name: '/snore', // Update this route name
      page: () => const SleepSound(), // Navigate to the SleepSound widget
    ),
    GetPage(
      transition: Transition.fadeIn,
      transitionDuration: const Duration(seconds: 2),
      name: '/face', // Update this route name
      page: () => const SnoreScreen(), // Navigate to the SleepSound widget
    ),
    GetPage(
        transition: Transition.downToUp,
        transitionDuration: const Duration(seconds: 2),
        name: '/dashboard',
        page: () => const DashBoard(),
        binding: BindingsBuilder(() {
          Get.put(ScanController());
        }))
  ];
}

```

lib\view\camera_view.dart

```dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simpleapp/controller/scan_controller.dart';

class CameraView extends GetView<ScanController> {
  const CameraView({super.key});

  // Map to store class names and their associated colors
  static const Map<String, Color> classColors = {
    'Mata terbuka': Colors.green,
    'Mata tertutup': Colors.red,
    'Mata tertutup setengah': Colors.yellow,
    'Mulut terbuka': Colors.red,
    'Mulut terbuka setengah': Colors.orange,
    'Mulut tertutup': Colors.cyan,
    'Wajah': Colors.pink,
  };

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        final isDarkMode = controller.isDarkMode.value;
        final theme = isDarkMode ? ThemeData.dark() : ThemeData.light();
        return MaterialApp(
          theme: theme,
          home: Scaffold(
            backgroundColor: isDarkMode ? Colors.black : Colors.white,
            body: Obx(
              () {
                if (controller.isCameraInit.value) {
                  return Stack(
                    children: [
                      CameraPreview(controller.cameraController),
                      ...controller.boundingBoxes.value.map(
                        (box) => Positioned(
                          left: (box.key['left'] ?? 0.0) *
                              MediaQuery.of(context).size.width,
                          top: (box.key['top'] ?? 0.0) *
                              MediaQuery.of(context).size.height,
                          child: Container(
                            width: ((box.key['right'] ?? 0.0) -
                                    (box.key['left'] ?? 0.0)) *
                                MediaQuery.of(context).size.width,
                            height: ((box.key['bottom'] ?? 0.0) -
                                    (box.key['top'] ?? 0.0)) *
                                MediaQuery.of(context).size.height,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: classColors[box.value] ??
                                    Colors
                                        .green, // Use the mapped color or default to green
                                width: 2,
                              ),
                            ),
                            child: Text(
                              box.value ?? '',
                              style: TextStyle(
                                color: classColors[box.value] ??
                                    Colors
                                        .green, // Use the mapped color or default to green
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 20,
                        right: 20,
                        child: FloatingActionButton(
                          onPressed: controller.switchCamera,
                          child: const Icon(Icons.switch_camera),
                        ),
                      ),
                      Positioned(
                        bottom: 20,
                        left: 20,
                        child: Row(
                          children: controller.capturedImages
                              .value // Convert RxList to regular list
                              .toList()
                              .reversed // Reverse the list to get the last two elements
                              .take(2) // Take the last two images
                              .map(
                            (imageData) {
                              // Check if imageData is null (indicating an error occurred)
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    image: DecorationImage(
                                      image: MemoryImage(imageData),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              );
                                                        },
                          ).toList(), // Convert map result to list
                        ),
                      ),
                      Positioned(
                        top: 20,
                        left: 20,
                        child: IconButton(
                          icon: Icon(
                            isDarkMode ? Icons.dark_mode : Icons.light_mode,
                            color: isDarkMode ? Colors.white : Colors.black,
                          ),
                          onPressed: controller.toggleDarkMode,
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Obx(() {
                          if (!controller.showSlider.value) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 20),
                                SizedBox(
                                  width:
                                      MediaQuery.of(context).size.width * 0.5,
                                  child: LinearProgressIndicator(
                                    value: controller.mataTertutupFrameCount /
                                        controller.eyeDurationThreshold.value,
                                    backgroundColor: Colors.grey,
                                    valueColor: const AlwaysStoppedAnimation<Color>(
                                        Colors.red),
                                  ),
                                ),
                                const Text("Indikator progress alarm menyala"),
                                const SizedBox(height: 20),
                                ElevatedButton(
                                  onPressed: () {
                                    controller.showSlider.value = true;
                                  },
                                  child: const Text("Settings"),
                                ),
                              ],
                            );
                          } else {
                            return const SizedBox.shrink();
                          }
                        }),
                      ),
                      Obx(
                        () {
                          if (controller.showSlider.value) {
                            return AlertDialog(
                              title: const Text("Set Alarm Delay"),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Slider(
                                    value: controller.eyeDurationThreshold.value
                                        .toDouble(),
                                    max: 5.0,
                                    min: 1.0,
                                    divisions: 4,
                                    label: controller.eyeDurationThreshold.value
                                        .toString(),
                                    onChanged: (value) {
                                      controller.eyeDurationThreshold.value =
                                          value.toInt();
                                    },
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    controller.showSlider.value = false;
                                    controller.testOut();
                                  },
                                  child: const Text("Close"),
                                ),
                              ],
                            );
                          } else {
                            return const SizedBox.shrink();
                          }
                        },
                      ),
                    ],
                  );
                } else {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }
}

```

lib\view\component\buttonlist.dart

```dart
import 'package:flutter/material.dart';

class ButtonList extends StatelessWidget {
  const ButtonList({
    this.onTap,
    required this.title,
    required this.deskripsi,
    required this.imagePath,
    super.key,
  });

  final String title;
  final String deskripsi;
  final String imagePath;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      splashColor: Colors.blue,
      borderRadius: BorderRadius.circular(15.0),
      onTap: onTap,
      child: Ink(
        height: 100,
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 0, 204, 255),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.deepOrange),
        ),
        child: Padding(
          padding: const EdgeInsets.all(5.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontFamily: 'Montserrat',
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      Text(
                        deskripsi,
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        softWrap: true,
                        maxLines:
                            2, // Ensure it wraps within a maximum of two lines
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: 80,
                height: 90, // Adjusted to fill the height
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  image: DecorationImage(
                    image: AssetImage("assets/images/$imagePath.png"),
                    fit: BoxFit.cover,
                  ),
                  border: Border.all(color: Colors.black),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

```

lib\view\config.dart

```dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock/wakelock.dart';
import 'package:get/get.dart';

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  _ConfigPageState createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  bool _wakelockEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadWakelockStatus();
  }

  Future<void> _loadWakelockStatus() async {
    final isEnabled = await Wakelock.enabled;
    setState(() {
      _wakelockEnabled = isEnabled;
    });
  }

  Future<void> _toggleWakelock(bool value) async {
    if (value) {
      await Wakelock.enable();
    } else {
      await Wakelock.disable();
    }
    setState(() {
      _wakelockEnabled = value;
    });
  }

  Future<void> _clearStatistics() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('sleepCount');
    Get.snackbar(
      'Success',
      'Statistics cleared',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Config'),
        backgroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text(
                'Enable WakeLock',
                style: TextStyle(
                  fontSize: 20,
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              value: _wakelockEnabled,
              onChanged: _toggleWakelock,
              activeColor: Colors.orange,
              inactiveThumbColor: Colors.grey,
              inactiveTrackColor: Colors.grey.shade400,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.black, backgroundColor: Colors.orange,
              ),
              onPressed: _clearStatistics,
              child: const Text('Clear Statistics'),
            ),
          ],
        ),
      ),
    );
  }
}

```

lib\view\dashboard.dart

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:simpleapp/controller/scan_controller.dart';

class DashBoard extends GetView<ScanController> {
  const DashBoard({super.key}); // Removed const

  @override
  Widget build(BuildContext context) {
    return const DashBoardContent();
  }
}

class DashBoardContent extends StatefulWidget {
  const DashBoardContent({super.key});

  @override
  _DashBoardContentState createState() => _DashBoardContentState();
}

class _DashBoardContentState extends State<DashBoardContent> {
  InterstitialAd? _interstitialAd;

  @override
  void initState() {
    super.initState();
    _loadInterstitialAd();
  }

  @override
  void dispose() {
    _interstitialAd?.dispose();
    super.dispose();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: 'ca-app-pub-6421780469600966/3968343512', // Test ad unit ID
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;
        },
        onAdFailedToLoad: (LoadAdError error) {
          print('InterstitialAd failed to load: $error');
        },
      ),
    );
  }

  void _showInterstitialAd(VoidCallback onAdDismissed) {
    if (_interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (InterstitialAd ad) {
          ad.dispose();
          _loadInterstitialAd();
          onAdDismissed();
        },
        onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
          ad.dispose();
          _loadInterstitialAd();
          onAdDismissed();
        },
      );
      _interstitialAd!.show();
    } else {
      // If the ad isn't available, just proceed with the navigation
      onAdDismissed();
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showWarningModal(context);
    });

    final List<Widget> imageSliders = [
      buildCarouselItem(
        title: "Fast Sleep Detector",
        description: "Use faster method to detect sleep (recommended)",
        imagePath: "assets/images/rocket.jpg",
        onTap: () {
          _showInterstitialAd(() {
            Get.toNamed('/face');
          });
        },
      ),
      buildCarouselItem(
        title: "Sleep Detector",
        description: "Detect if you're feeling sleepy",
        imagePath: "assets/images/driving.jpg",
        onTap: () {
          _showInterstitialAd(() {
            Get.find<ScanController>()
                .checkPermission(Permission.camera, "Sleep Detector");
          });
        },
      ),
      buildCarouselItem(
        title: "Virtual Deadman Pedal",
        description: "Set a quiet alarm to wake you up gently",
        imagePath: "assets/images/pedal.jpg",
        onTap: () {
          _showInterstitialAd(() {
            Get.toNamed('/snore');
          });
        },
      ),
      buildCarouselItem(
        title: "Config",
        description: "Set Global Config",
        imagePath: "assets/images/gear.jpg",
        onTap: () {
          _showInterstitialAd(() {
            Get.toNamed('/config');
          });
        },
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: FutureBuilder<int>(
          future: _loadSleepCount(),
          builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return const Center(child: Text("Error loading sleep count"));
            } else {
              final sleepCount = snapshot.data ?? 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 50),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 15.0),
                    child: Text(
                      "Anti-Tidur",
                      style: TextStyle(
                        fontSize: 40,
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 60),
                  CarouselSlider(
                    items: imageSliders,
                    options: CarouselOptions(
                      enlargeCenterPage: true,
                      enableInfiniteScroll: true,
                      autoPlay: true,
                      height: 400,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20.0),
                    child: Divider(
                      color: Colors.white, // Change the color as needed
                      thickness: 1.0, // Adjust the thickness as needed
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 15.0),
                    child: Text(
                      "Statistics",
                      style: TextStyle(
                        fontSize: 30,
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15.0),
                    child: Text(
                      "The number you detected sleep cumulative: $sleepCount",
                      style: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'Montserrat',
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              );
            }
          },
        ),
      ),
    );
  }

  Future<int> _loadSleepCount() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getInt('sleepCount') ?? 0;
  }

  Widget buildCarouselItem({
    required String title,
    required String description,
    required String imagePath,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(5.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15.0),
          image: DecorationImage(
            image: AssetImage(imagePath),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15.0),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.1),
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(15.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    description,
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    softWrap: true,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showWarningModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => Container(
      padding: const EdgeInsets.all(16.0),
      color: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Peringatan, AI ini masih memiliki kelemahan di bidang berikut:",
            style: TextStyle(
              fontSize: 18,
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "* Bias terhadap usia: Semakin tua usia, semakin lebih terdeteksi ngantuk\n"
            "* Performa berkurang ketika cahaya gelap\n"
            "* Tidak bisa mendeteksi ngantuk secara akurat\n"
            "* Memiliki performa yang agak buruk ketika wajah menggunakan masker",
            style: TextStyle(
              fontSize: 16,
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.black, backgroundColor: Colors.orange,
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Tutup"),
            ),
          ),
        ],
      ),
    ),
  );
}

```

lib\view\sleep.dart

```dart
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:iirjdart/butterworth.dart';
import 'dart:async';
import 'dart:math';
import 'package:vibration/vibration.dart';

final player = AudioPlayer();

class SleepSound extends StatefulWidget {
  const SleepSound({Key? key}) : super(key: key);

  @override
  _SleepSoundState createState() => _SleepSoundState();
}

class _SleepSoundState extends State<SleepSound> {
  bool _isRecording = false;
  final List<double> _decibelsHistory = [];
  static const int maxHistoryLength = 100;
  double _dbThreshold = 70.0; // Default threshold value in dB
  late FlutterAudioCapture _audioCapture;
  late Butterworth _butterworth;
  StreamSubscription<dynamic>? _audioStreamSubscription;
  double _progress = 0.0; // Progress bar value
  static const int progressIncrement = 1; // Progress increment value
  late Timer _progressTimer;
  double _interval = 500;

  @override
  void initState() {
    super.initState();
    _audioCapture = FlutterAudioCapture();
    _butterworth = Butterworth();

    _initRecorder();
  }

  Future<void> _initRecorder() async {
    if (await Permission.microphone.request().isGranted) {
      print("Microphone permission granted");
    } else {
      print("Microphone permission denied");
    }
  }

  void startRecording() async {
    setState(() {
      _isRecording = true;
    });

    _butterworth.highPass(4, 44100,
        250); // 4th order Butterworth high-pass filter, cutoff frequency 250 Hz

    _audioCapture.start(
      _captureHandler,
      _onError,
      sampleRate: 44100,
      bufferSize: 3000,
    );

    print("Recording started");

    // Start the progress timer
    _startProgressTimer();
  }

  void _startProgressTimer() {
    _progressTimer =
        Timer.periodic(Duration(milliseconds: _interval.toInt()), (timer) {
      if (_progress >= 100) {
        _triggerFullProgressAction();
      } else {
        setState(() {
          _progress += progressIncrement;
        });
      }
    });
  }

  void _triggerFullProgressAction() async {
    print("Progress bar is full! Triggering action...");
    _stopAllActivities();
    Vibration.vibrate(duration: 1000); // Vibrate the device for 1 second
    await player.setLoopMode(LoopMode.one); // Set the player to loop the audio
    await player.setAsset('assets/warn.mp3'); // Set the audio file
    player.play(); // Start playing the warning sound

    // Show the popup modal
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Inactivity Detected'),
          content: const Text(
              'Inactivity detected from you, now please close this button to turn off the alarm'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _resumeAllActivities();
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _stopAllActivities() {
    stopRecording();
    player.stop();
    _resetProgress();
  }

  void _resumeAllActivities() {
    startRecording();
    player.stop();
  }

  void _resetProgress() {
    setState(() {
      _progress = 0.0;
    });
  }

  void _captureHandler(dynamic data) async {
    List<double> audioData = List<double>.from(data);

    // Apply high-pass filter
    List<double> filteredData =
        audioData.map((sample) => _butterworth.filter(sample)).toList();

    // Calculate the decibel level
    double decibel = _calculateDecibel(filteredData);
    decibel += 100;
    print('Filtered Noise: $decibel dB');

    setState(() {
      _decibelsHistory.add(decibel);
      if (_decibelsHistory.length > maxHistoryLength) {
        _decibelsHistory.removeAt(0);
      }
    });

    // Reset progress if decibel level exceeds threshold
    if (decibel >= _dbThreshold) {
      _resetProgress();
    }
  }

  void _onError(Object error) {
    print(error.toString());
    setState(() {
      _isRecording = false;
    });
  }

  double _calculateDecibel(List<double> audioData) {
    double sum = 0.0;
    for (double sample in audioData) {
      sum += sample * sample;
    }
    double rms = sqrt(sum / audioData.length);
    double decibel = 20 * (log(rms) / ln10); // Convert natural log to base 10
    return decibel;
  }

  void stopRecording() async {
    setState(() {
      _isRecording = false;
    });
    await _audioCapture.stop();
    _audioStreamSubscription?.cancel();
    _progressTimer.cancel();
  }

  @override
  void dispose() {
    _audioStreamSubscription?.cancel();
    _progressTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Set background color to black
      appBar: AppBar(
        title: const Text(
          'Virtual Deadman Pedal',
          style: TextStyle(
            color: Colors.white, // Set text color to white
            fontFamily: 'Montserrat', // Use the Montserrat font family
            fontWeight: FontWeight.bold, // Use bold font weight
          ),
        ),
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _isRecording ? stopRecording : startRecording,
              child: Text(
                _isRecording ? 'Stop Deadman Pedal' : 'Start Deadman Pedal',
                style: const TextStyle(
                  color:
                      Color.fromARGB(255, 54, 0, 85), // Set text color to white
                  fontFamily: 'Montserrat', // Use the Montserrat font family
                  fontWeight: FontWeight.bold, // Use bold font weight
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              width: double.infinity,
              child: CustomPaint(
                painter: DecibelMeterPainter(_decibelsHistory, _dbThreshold),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Threshold: ${_dbThreshold.toStringAsFixed(1)} dB',
              style: const TextStyle(
                color: Colors.white, // Set text color to white
                fontFamily: 'Montserrat', // Use the Montserrat font family
                fontWeight: FontWeight.bold, // Use bold font weight
              ),
            ),
            Slider(
              value: _dbThreshold,
              min: 30,
              max: 100,
              divisions: 70,
              label: _dbThreshold.toStringAsFixed(1),
              onChanged: (double value) {
                setState(() {
                  _dbThreshold = value;
                });
              },
            ),
            Text(
              'Progress Bar buildup: ${_interval.toStringAsFixed(1)} ms',
              style: const TextStyle(
                color: Colors.white, // Set text color to white
                fontFamily: 'Montserrat', // Use the Montserrat font family
                fontWeight: FontWeight.bold, // Use bold font weight
              ),
            ),
            Slider(
              value: _interval,
              min: 100,
              max: 1000,
              divisions: 9,
              label: _interval.toStringAsFixed(1),
              onChanged: (double value) {
                setState(() {
                  _interval = value;
                });
              },
            ),
            const SizedBox(height: 20),
            LinearProgressIndicator(
              value: _progress / 100,
            ),
            const SizedBox(height: 20),
            Text(
              'Progress: ${_progress.toStringAsFixed(1)}%',
              style: const TextStyle(
                color: Colors.white, // Set text color to white
                fontFamily: 'Montserrat', // Use the Montserrat font family
                fontWeight: FontWeight.bold, // Use bold font weight
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DecibelMeterPainter extends CustomPainter {
  final List<double> decibelsHistory;
  final double dbThreshold;

  DecibelMeterPainter(this.decibelsHistory, this.dbThreshold);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint backgroundPaint = Paint()
      ..color = const Color.fromARGB(255, 19, 95, 0);
    final Paint linePaint = Paint()
      ..color = const Color.fromARGB(255, 255, 129, 238)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    final Paint thresholdPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    if (decibelsHistory.isEmpty) {
      return; // Nothing to draw
    }

    const double maxDecibel = 120.0;
    const double minDecibel = 0.0;

    for (int i = 0; i < decibelsHistory.length - 1; i++) {
      final double x1 = (i / (decibelsHistory.length - 1)) * size.width;
      final double y1 = size.height -
          ((decibelsHistory[i] - minDecibel) / (maxDecibel - minDecibel)) *
              size.height;
      final double x2 = ((i + 1) / (decibelsHistory.length - 1)) * size.width;
      final double y2 = size.height -
          ((decibelsHistory[i + 1] - minDecibel) / (maxDecibel - minDecibel)) *
              size.height;

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), linePaint);
    }

    // Draw threshold line
    final double thresholdY = size.height -
        ((dbThreshold - minDecibel) / (maxDecibel - minDecibel)) * size.height;
    canvas.drawLine(
        Offset(0, thresholdY), Offset(size.width, thresholdY), thresholdPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

```

lib\view\snore.dart

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:just_audio/just_audio.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:math' as math;
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';

final player = AudioPlayer();

double root(num value, num rootDegree) {
  if (rootDegree <= 0) {
    throw ArgumentError('Must be positive');
  }
  return math.pow(value, 1 / rootDegree).toDouble();
}

class SnoreScreen extends StatefulWidget {
  const SnoreScreen({super.key});

  @override
  _SnoreScreenState createState() => _SnoreScreenState();
}

class _SnoreScreenState extends State<SnoreScreen> {
  late Future<void> _initializeControllerFuture;
  late CameraController _cameraController;
  late FaceDetector _faceDetector;
  bool isDetecting = false;
  bool frontCamera = false;

  double? leftEyeOpenProb;
  double? rightEyeOpenProb;
  double? smileProb;
  int? trackingId;
  List<Point<int>> landmarks = [];
  int _cameraIndex = 0;
  bool _isDarkMode = false;
  bool isPlaying = false;
  int threshold = 10;
  int currentProgress = 0;
  double activThreshold = 0.5;
  List<double> leftEyeHistory = [];
  List<double> rightEyeHistory = [];
  double cameraWidth = 0.0;
  double cameraHeight = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeFaceDetector();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    _cameraController = CameraController(
      cameras[_cameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    _initializeControllerFuture = _cameraController.initialize();
    await _initializeControllerFuture;

    final camera = _cameraController.description;
    frontCamera = camera.lensDirection == CameraLensDirection.front;

    setState(() {
      cameraWidth = _cameraController.value.previewSize?.width ?? 0.0;
      cameraHeight = _cameraController.value.previewSize?.height ?? 0.0;
    });
  }

  void _switchCamera() async {
    final cameras = await availableCameras();
    _cameraIndex = (_cameraIndex + 1) % cameras.length;
    await _cameraController.dispose();
    _initializeCamera();
  }

  void _initializeFaceDetector() {
    final options = FaceDetectorOptions(
      enableContours: false,
      enableLandmarks: true,
      enableClassification: true,
    );
    _faceDetector = FaceDetector(options: options);
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _faceDetector.close();
    super.dispose();
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _cameraController.description;
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;

    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      final rotationCompensation =
          _orientations[_cameraController.value.deviceOrientation] ?? 0;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotation = InputImageRotationValue.fromRawValue(
            (sensorOrientation + rotationCompensation) % 360);
      } else {
        rotation = InputImageRotationValue.fromRawValue(
            (sensorOrientation - rotationCompensation + 360) % 360);
      }
    }

    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  void _detectFaces(CameraImage image) async {
    if (isDetecting) return;
    isDetecting = true;

    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) {
      isDetecting = false;
      return;
    }

    final List<Face> faces = await _faceDetector.processImage(inputImage);

    if (faces.isNotEmpty) {
      final face = faces.first;

      double leftEyeOpenProbNorm =
          face.leftEyeOpenProbability ?? 1.0; // Default to 1.0 if null
      double rightEyeOpenProbNorm =
          face.rightEyeOpenProbability ?? 1.0; // Default to 1.0 if null

      leftEyeHistory.add(leftEyeOpenProbNorm);
      rightEyeHistory.add(rightEyeOpenProbNorm);
      if (leftEyeHistory.length > 50) leftEyeHistory.removeAt(0);
      if (rightEyeHistory.length > 50) rightEyeHistory.removeAt(0);

      if (leftEyeOpenProbNorm < activThreshold ||
          rightEyeOpenProbNorm < activThreshold) {
        if (currentProgress < threshold) {
          currentProgress++;
        }
      } else {
        if (currentProgress >= 0) {
          currentProgress -= 2;
        } else {
          currentProgress = 0;
        }
      }

      if (currentProgress == threshold) {
        Vibration.vibrate(duration: 1000); // Vibrate the device for 1 second
        if (!isPlaying) {
          await player
              .setLoopMode(LoopMode.one); // Set the player to loop the audio
          await player.setAsset('assets/warn.mp3'); // Set the audio file
          player.play(); // Start playing the warning sound
          isPlaying = true;

          // Increment sleep count and save to local storage
          SharedPreferences prefs = await SharedPreferences.getInstance();
          int sleepCount = (prefs.getInt('sleepCount') ?? 0) + 1;
          await prefs.setInt('sleepCount', sleepCount);
        }
      } else {
        player.stop();
        isPlaying = false;
      }

      setState(() {
        leftEyeOpenProb = face.leftEyeOpenProbability;
        rightEyeOpenProb = face.rightEyeOpenProbability;
        smileProb = face.smilingProbability;
        trackingId = face.trackingId;
        landmarks = [
          face.landmarks[FaceLandmarkType.bottomMouth]?.position ?? const Point(0, 0),
          face.landmarks[FaceLandmarkType.leftMouth]?.position ?? const Point(0, 0),
          face.landmarks[FaceLandmarkType.rightMouth]?.position ?? const Point(0, 0),
          face.landmarks[FaceLandmarkType.leftEye]?.position ?? const Point(0, 0),
          face.landmarks[FaceLandmarkType.rightEye]?.position ?? const Point(0, 0),
          face.landmarks[FaceLandmarkType.noseBase]?.position ?? const Point(0, 0),
          face.landmarks[FaceLandmarkType.rightCheek]?.position ?? const Point(0, 0),
          face.landmarks[FaceLandmarkType.leftCheek]?.position ?? const Point(0, 0),
        ];
      });
    }

    isDetecting = false;
  }

  void _toggleDarkMode() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  void _showSettingsModal() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Settings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Delay before Alarm Activates',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  Slider(
                    value: threshold.toDouble(),
                    max: 20.0,
                    min: 2.0,
                    divisions: 9,
                    label: threshold.toString(),
                    onChanged: (value) {
                      setModalState(() {
                        threshold = value.toInt();
                      });
                      setState(
                          () {}); // Ensure the parent state is updated as well
                    },
                  ),
                  const Text(
                    'Activation Threshold',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  Slider(
                    value: activThreshold,
                    max: 1.0,
                    min: 0.1,
                    divisions: 9,
                    label: activThreshold.toString(),
                    onChanged: (value) {
                      setModalState(() {
                        activThreshold = value;
                      });
                      setState(
                          () {}); // Ensure the parent state is updated as well
                    },
                  ),
                  // Add sliders or other settings components here
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Sleepiness Detection (new)',
          style: TextStyle(
            color: _isDarkMode ? Colors.white : Colors.black,
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: _isDarkMode ? Colors.black : Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isDarkMode ? Icons.wb_sunny : Icons.nights_stay),
            onPressed: _toggleDarkMode,
          ),
          IconButton(
            icon: const Icon(Icons.switch_camera),
            onPressed: _switchCamera,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsModal,
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            _cameraController.startImageStream((image) => _detectFaces(image));
            return Stack(
              children: [
                CameraPreview(_cameraController),
                Positioned(
                  bottom: 50,
                  left: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Left Eye (Red):      ',
                            style: TextStyle(
                              color: _isDarkMode ? Colors.white : Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            width: 20,
                            height: 20 * (leftEyeOpenProb ?? 0.01),
                            decoration: const BoxDecoration(
                              image: DecorationImage(
                                image: AssetImage('assets/eye_icon.png'),
                                fit: BoxFit.fill,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            'Right Eye (Green): ',
                            style: TextStyle(
                              color: _isDarkMode ? Colors.white : Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            width: 20,
                            height: 20 * (rightEyeOpenProb ?? 0.01),
                            decoration: const BoxDecoration(
                              image: DecorationImage(
                                image: AssetImage('assets/eye_icon.png'),
                                fit: BoxFit.fill,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        width: MediaQuery.of(context).size.width * 0.5,
                        child: LinearProgressIndicator(
                          value: currentProgress / threshold,
                          backgroundColor: Colors.grey,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
                CustomPaint(
                  size: Size.infinite,
                  painter:
                      LandmarkPainter(landmarks, frontCamera, cameraHeight),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 150,
                    height: 150,
                    color: const Color.fromARGB(255, 84, 0, 105),
                    child: CustomPaint(
                      painter:
                          HistoryGraphPainter(leftEyeHistory, rightEyeHistory),
                    ),
                  ),
                ),
                ...landmarks.map((landmark) {
                  return Positioned(
                    left: frontCamera
                        ? 370 - root(landmark.x, 1.05).toDouble()
                        : root(landmark.x, 1.05).toDouble(),
                    top: root(landmark.y, 1.05).toDouble() +
                        20 * (landmark.y / cameraHeight),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color.fromARGB(255, 255, 0, 0),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }).toList(),
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
      backgroundColor: _isDarkMode ? Colors.black : Colors.white,
    );
  }
}

const _orientations = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

class LandmarkPainter extends CustomPainter {
  final List<Point<int>> landmarks;
  final bool frontCamera;
  double cameraHeight;

  LandmarkPainter(this.landmarks, this.frontCamera, this.cameraHeight);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw lines connecting original landmarks
    for (int i = 0; i < landmarks.length; i++) {
      for (int j = i + 1; j < landmarks.length; j++) {
        final p1 = landmarks[i];
        final p2 = landmarks[j];

        final x1 = frontCamera
            ? 370 - root(p1.x, 1.05).toDouble()
            : root(p1.x, 1.05).toDouble();
        final y1 = root(p1.y, 1.05).toDouble() + 20 * (p1.y / cameraHeight);
        final x2 = frontCamera
            ? 370 - root(p2.x, 1.05).toDouble()
            : root(p2.x, 1.05).toDouble();
        final y2 = root(p2.y, 1.05).toDouble() + 20 * (p2.y / cameraHeight);

        canvas.drawLine(
          Offset(x1, y1),
          Offset(x2, y2),
          paint,
        );
      }
    }

    // Draw lines connecting offset points
    for (int i = 0; i < landmarks.length; i++) {
      for (int j = i + 1; j < landmarks.length; j++) {
        final p1 = landmarks[i];
        final p2 = landmarks[j];

        const offset = 40; // offset distance
        final angle1 = atan2(p1.y - p2.y, p1.x - p2.x);
        final angle2 = atan2(p2.y - p1.y, p2.x - p1.x);

        final offsetX1 = offset * cos(angle1);
        final offsetY1 = offset * sin(angle1);
        final offsetX2 = offset * cos(angle2);
        final offsetY2 = offset * sin(angle2);

        final x1 = frontCamera
            ? 370 - root(p1.x, 1.05).toDouble() - offsetX1
            : root(p1.x, 1.05).toDouble() + offsetX1;
        final y1 =
            root(p1.y, 1.05).toDouble() + 20 * (p1.y / cameraHeight) + offsetY1;
        final x2 = frontCamera
            ? 370 - root(p2.x, 1.05).toDouble() - offsetX2
            : root(p2.x, 1.05).toDouble() + offsetX2;
        final y2 =
            root(p2.y, 1.05).toDouble() + 20 * (p2.y / cameraHeight) + offsetY2;

        canvas.drawLine(
          Offset(x1, y1),
          Offset(x2, y2),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate != this;
  }
}

class HistoryGraphPainter extends CustomPainter {
  final List<double> leftEyeData;
  final List<double> rightEyeData;

  HistoryGraphPainter(this.leftEyeData, this.rightEyeData);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final pathLeft = Path();
    final pathRight = Path();

    double widthStep = size.width / (leftEyeData.length - 1);

    pathLeft.moveTo(0, size.height * (1 - leftEyeData[0]));
    pathRight.moveTo(0, size.height * (1 - rightEyeData[0]));

    for (int i = 1; i < leftEyeData.length; i++) {
      pathLeft.lineTo(i * widthStep, size.height * (1 - leftEyeData[i]));
      pathRight.lineTo(i * widthStep, size.height * (1 - rightEyeData[i]));
    }

    paint.color = Colors.red;
    canvas.drawPath(pathLeft, paint);

    paint.color = Colors.green;
    canvas.drawPath(pathRight, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

```

