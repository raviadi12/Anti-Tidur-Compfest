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
