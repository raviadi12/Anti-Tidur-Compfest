import 'package:get/get.dart';
import 'package:simpleapp/controller/scan_controller.dart';
import 'package:simpleapp/view/camera_view.dart';
import 'package:simpleapp/view/dashboard.dart';
import 'package:simpleapp/view/config.dart';

class AppRoutes {
  static final pages = [
    GetPage(
      transition: Transition.zoom, // Use zoom transition
      transitionDuration: const Duration(milliseconds: 500), // 0.5 seconds
      name: '/home',
      page: () => const CameraView(),
    ),
    GetPage(
      transition: Transition.zoom,
      transitionDuration: const Duration(milliseconds: 500),
      name: '/config',
      page: () => const ConfigPage(),
    ),
    GetPage(
        transition: Transition.zoom,
        transitionDuration: const Duration(milliseconds: 500),
        name: '/dashboard',
        page: () => const DashBoard(),
        binding: BindingsBuilder(() {
          Get.put(ScanController());
        }))
  ];
}
