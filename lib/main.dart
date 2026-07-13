
import 'package:flutter/material.dart';
import 'package:ats_onework/management/manager_login.dart';
import 'package:ats_onework/employee/employee_login.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ATS OneWork',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
      ),
      home: const PortalLandingScreen(),
    );
  }
}

class PortalLandingScreen extends StatelessWidget {
  const PortalLandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Premium Cyber-Gold Obsidian Palette
    const Color obsidianBlack = Color(0xFF0D0D11);
    const Color darkCharcoal = Color(0xFF16161F);
    const Color champagneGold = Color(0xFFE2B93B);
    const Color textFrost = Color(0xFFF3F4F6);
    const Color textMuted = Color(0xFF9CA3AF);

    return Scaffold(
      backgroundColor: obsidianBlack,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(32.0),
            decoration: BoxDecoration(
              color: darkCharcoal,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: champagneGold.withValues(alpha: 0.12), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                // Custom Styled Logo matching brand requirements
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: obsidianBlack,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: champagneGold.withValues(alpha: 0.3), width: 1.5),
                      ),
                    ),
                    Positioned(
                      top: 18,
                      child: Icon(Icons.keyboard_arrow_up_rounded, size: 52, color: champagneGold.withValues(alpha: 0.95)),
                    ),
                    Positioned(
                      bottom: 22,
                      child: Icon(Icons.star_rounded, size: 14, color: champagneGold.withValues(alpha: 0.9)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Typography with split coloring matching your screenshot
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'ATS ',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: textFrost, letterSpacing: 0.5),
                    ),
                    Text(
                      'OneWork',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: champagneGold, letterSpacing: 0.5),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Enterprise Resource Portal',
                  style: TextStyle(fontSize: 13, color: textMuted.withValues(alpha: 0.7), fontWeight: FontWeight.w500, letterSpacing: 0.5),
                ),
                const SizedBox(height: 40),

                // Employee Portal Secondary Action Option
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const EmployeeLoginScreen()),
                );
                },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: champagneGold.withValues(alpha: 0.4), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      foregroundColor: champagneGold,
                    ),
                    child: const Text('Employee Portal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 16),

                // Management Portal Primary Solid Action Option
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ManagerLoginScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: champagneGold,
                      foregroundColor: obsidianBlack,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Management Portal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}