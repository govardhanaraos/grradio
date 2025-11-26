// 💡 NEW: More Screen - Default Page
import 'package:flutter/material.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          'More Options',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey.shade800,
          ),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFFF57C00), // Dark Orange
                Color(0xFFFFB74D), // Light Orange
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Info Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.blue.shade600,
                            Colors.purple.shade600,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.3),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.radio_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'GR Radio',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey.shade800,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Your Ultimate Music Companion',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 20),

            // Settings Section
            Text(
              'Settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey.shade800,
              ),
            ),
            SizedBox(height: 12),

            _buildSettingsItem(
              icon: Icons.notifications,
              title: 'Notifications',
              subtitle: 'Manage your notification preferences',
              color: Colors.orange.shade600,
            ),

            _buildSettingsItem(
              icon: Icons.volume_up,
              title: 'Audio Quality',
              subtitle: 'Adjust streaming and download quality',
              color: Colors.green.shade600,
            ),

            _buildSettingsItem(
              icon: Icons.storage,
              title: 'Storage',
              subtitle: 'Manage downloaded files and cache',
              color: Colors.blue.shade600,
            ),

            _buildSettingsItem(
              icon: Icons.nightlight_round,
              title: 'Dark Mode',
              subtitle: 'Switch between light and dark themes',
              color: Colors.purple.shade600,
            ),

            SizedBox(height: 20),

            // Support Section
            Text(
              'Support',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey.shade800,
              ),
            ),
            SizedBox(height: 12),

            _buildSettingsItem(
              icon: Icons.help_outline,
              title: 'Help & Support',
              subtitle: 'Get help and contact support',
              color: Colors.red.shade600,
            ),

            _buildSettingsItem(
              icon: Icons.star_rate,
              title: 'Rate App',
              subtitle: 'Share your feedback with us',
              color: Colors.amber.shade600,
            ),

            _buildSettingsItem(
              icon: Icons.share,
              title: 'Share App',
              subtitle: 'Share with your friends',
              color: Colors.teal.shade600,
            ),

            _buildSettingsItem(
              icon: Icons.info_outline,
              title: 'About',
              subtitle: 'App version and information',
              color: Colors.blueGrey.shade600,
            ),

            SizedBox(height: 30),

            // App Version
            Center(
              child: Text(
                'Version 1.0.0',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Card(
      margin: EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey.shade400,
        ),
        onTap: () {
          // Handle item tap
          print('$title tapped');
        },
      ),
    );
  }
}
