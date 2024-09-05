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
