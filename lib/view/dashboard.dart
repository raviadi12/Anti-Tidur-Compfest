import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showWarningModal(context);
    });

    final List<Widget> imageSliders = [
      buildCarouselItem(
        title: "Sleep Detector",
        description: "Detect if you're feeling sleepy",
        imagePath: "assets/images/driving.jpg",
        onTap: () {
          Get.find<ScanController>()
              .checkPermission(Permission.camera, "Sleep Detector");
        },
      ),
      buildCarouselItem(
        title: "Config",
        description: "Set Global Config",
        imagePath: "assets/images/gear.jpg",
        onTap: () {
          Get.toNamed('/config');
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
                foregroundColor: Colors.black,
                backgroundColor: Colors.orange,
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
