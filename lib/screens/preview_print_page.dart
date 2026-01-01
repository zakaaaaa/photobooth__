// preview_print_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:photobooth_app/providers/photo_provider.dart';
import 'package:photobooth_app/screens/splash_screen.dart';
import 'package:photobooth_app/widgets/photo_frame_widget.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class PreviewPrintPage extends StatefulWidget {
  const PreviewPrintPage({super.key});

  @override
  State<PreviewPrintPage> createState() => _PreviewPrintPageState();
}

class _PreviewPrintPageState extends State<PreviewPrintPage> {
  final GlobalKey _previewKey = GlobalKey();
  final TextEditingController _emailController = TextEditingController();
  bool _isProcessing = false;
  bool _isSendingEmail = false;

  // ============================================================
  // KONFIGURASI SMTP - GANTI INI DENGAN EMAIL & PASSWORD ANDA
  // ============================================================
  final String SMTP_EMAIL = 'zakakurnia0@gmail.com';        // ← GANTI INI
  final String SMTP_PASSWORD = 'tlrw yvdg ocgv aret';   // ← GANTI INI (16 karakter dari Google)
  // ============================================================

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<Uint8List?> _capturePreview() async {
    try {
      RenderRepaintBoundary boundary = _previewKey.currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      print('Error capturing preview: $e');
      return null;
    }
  }

  Future<void> _printLayout() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final imageBytes = await _capturePreview();
      if (imageBytes == null) {
        throw Exception('Failed to capture preview');
      }

      final pdf = pw.Document();
      final image = pw.MemoryImage(imageBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(image),
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Print job sent successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _saveImage() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final imageBytes = await _capturePreview();
      if (imageBytes == null) {
        throw Exception('Failed to capture preview');
      }

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${directory.path}/photobooth_$timestamp.png';
      
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image saved to: $filePath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _sendEmail() async {
    final recipientEmail = _emailController.text.trim();
    
    // Validasi email
    if (recipientEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an email address'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validasi format email sederhana
    if (!recipientEmail.contains('@') || !recipientEmail.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check jika SMTP belum disetup
    if (SMTP_EMAIL == 'YOUR_EMAIL@gmail.com' || SMTP_PASSWORD == 'your app password here') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ SMTP not configured! Please update SMTP_EMAIL and SMTP_PASSWORD in code'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    setState(() {
      _isSendingEmail = true;
    });

    try {
      print('📧 Preparing to send email...');
      
      // Capture image
      final imageBytes = await _capturePreview();
      if (imageBytes == null) {
        throw Exception('Failed to capture preview');
      }

      // Save temporary file
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${directory.path}/photobooth_$timestamp.png';
      
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);
      print('💾 Image saved to: $filePath');

      // ============================================================
      // SMTP Configuration - Gmail
      // ============================================================
      print('🔐 Connecting to Gmail SMTP...');
      final smtpServer = gmail(SMTP_EMAIL, SMTP_PASSWORD);
      
      // Alternative SMTP servers (uncomment jika pakai provider lain):
      // final smtpServer = hotmail(SMTP_EMAIL, SMTP_PASSWORD); // Outlook/Hotmail
      // final smtpServer = yahoo(SMTP_EMAIL, SMTP_PASSWORD);    // Yahoo
      // ============================================================
      
      // Create email message
      print('📝 Creating email message...');
      final message = Message()
        ..from = Address(SMTP_EMAIL, 'Photobooth App')
        ..recipients.add(recipientEmail)
        ..subject = 'Your Photobooth Image - ${DateTime.now().toString().split('.')[0]}'
        ..text = 'Thank you for using our Photobooth!\n\nPlease find your photo attached.'
        ..html = '''
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <h2 style="color: #4A6FFF;">Your Photobooth Image 📸</h2>
            <p>Thank you for using our Photobooth!</p>
            <p>Please find your photo attached below.</p>
            <br>
            <hr style="border: 1px solid #e0e0e0;">
            <p style="color: #666; font-size: 12px;">
              <small>Generated on ${DateTime.now().toString().split('.')[0]}</small>
            </p>
          </div>
        '''
        ..attachments.add(FileAttachment(file));

      // Send email
      print('📤 Sending email...');
      final sendReport = await send(message, smtpServer);
      print('✅ Email sent successfully: ${sendReport.toString()}');

      // Delete temp file
      try {
        await file.delete();
        print('🗑️ Temp file deleted');
      } catch (e) {
        print('Warning: Could not delete temp file: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Email sent successfully to $recipientEmail'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        
        // Clear email field
        _emailController.clear();
      }
    } on MailerException catch (e) {
      print('❌ Email sending failed: $e');
      if (mounted) {
        String errorMessage = 'Failed to send email';
        
        // Handle specific errors
        if (e.toString().contains('Authentication') || e.toString().contains('Invalid credentials')) {
          errorMessage = '❌ Email authentication failed!\n\nPlease check:\n• SMTP_EMAIL is correct\n• SMTP_PASSWORD is your App Password (not regular password)\n• App Password generated from: myaccount.google.com/apppasswords';
        } else if (e.toString().contains('Connection')) {
          errorMessage = 'Could not connect to email server. Check internet connection.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 7),
          ),
        );
      }
    } catch (e) {
      print('❌ Email error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      setState(() {
        _isSendingEmail = false;
      });
    }
  }

  void _goHome() {
    Provider.of<PhotoProvider>(context, listen: false).reset();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3A50E0), Color(0xFFFFFFFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  'Preview & Print',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ),
              
              // Preview Area
              Expanded(
                child: Row(
                  children: [
                    // Left Panel - Preview Photos
                    Expanded(
                      flex: 2,
                      child: RepaintBoundary(
                        key: _previewKey,
                        child: _buildPreviewPanel(),
                      ),
                    ),
                    
                    // Right Panel - Email Form
                    Expanded(
                      flex: 3,
                      child: _buildEmailPanel(),
                    ),
                  ],
                ),
              ),
              
              // Action Buttons
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Save Button
                    _buildActionButton(
                      'Save',
                      Icons.save,
                      Colors.green,
                      _saveImage,
                    ),
                    
                    // Print Button
                    _buildActionButton(
                      'Print',
                      Icons.print,
                      Colors.blue,
                      _printLayout,
                    ),
                    
                    // Done Button
                    _buildActionButton(
                      'Done',
                      Icons.home,
                      Colors.orange,
                      _goHome,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewPanel() {
    return Consumer<PhotoProvider>(
      builder: (context, provider, _) {
        const double frameWidth = 270;
        const double frameHeight = 600;
        const double photoWidth = 230;
        const double photoHeight = 150;
        const double photoSpacing = 3.5;

        return Center(
          child: Container(
            width: frameWidth,
            height: frameHeight,
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: provider.frameContainerTexture != null
                  ? null
                  : provider.frameContainerColor,
              image: provider.frameContainerTexture != null
                  ? DecorationImage(
                      image: AssetImage(provider.frameContainerTexture!),
                      fit: BoxFit.cover,
                    )
                  : null,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  ...provider.photos.asMap().entries.map((entry) {
                    final index = entry.key;
                    return Positioned(
                      left: (frameWidth - photoWidth) / 2,
                      top: 55 + index * (photoHeight + photoSpacing),
                      child: PhotoFrameWidget(
                        imageData: entry.value.imageData,
                        frameColor: provider.frameColor,
                        frameTexture: provider.frameTexture,
                        frameShape: provider.frameShape,
                        width: photoWidth,
                        height: photoHeight,
                      ),
                    );
                  }).toList(),

                  if (provider.headlineText.isNotEmpty)
                    Positioned(
                      left: provider.textPosition.dx,
                      top: provider.textPosition.dy,
                      child: Transform.rotate(
                        angle: provider.textRotation,
                        child: Text(
                          provider.headlineText,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: provider.textSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),

                  ...provider.stickers.map((sticker) {
                    return Positioned(
                      left: sticker.position.dx,
                      top: sticker.position.dy,
                      child: Transform.rotate(
                        angle: sticker.rotation,
                        child: Image.asset(
                          sticker.assetPath,
                          width: sticker.size,
                          height: sticker.size,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.star,
                              size: sticker.size,
                              color: Colors.yellow,
                            );
                          },
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmailPanel() {
    // Check if SMTP is configured
    final bool isSmtpConfigured = 
        SMTP_EMAIL != 'YOUR_EMAIL@gmail.com' && 
        SMTP_PASSWORD != 'your app password here';

    return Container(
      margin: const EdgeInsets.all(40),
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Icon
            Icon(
              Icons.email,
              size: 80,
              color: isSmtpConfigured ? Colors.blue[700] : Colors.orange[700],
            ),
            
            const SizedBox(height: 30),
            
            // Title
            Text(
              'Send to Email',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.blue[700],
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 10),
            
            // Subtitle
            const Text(
              'Enter recipient email address',
              style: TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 30),
            
            // Email Input Field
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Recipient Email',
                hintText: 'example@email.com',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(color: Colors.blue[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(color: Colors.blue[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(color: Colors.blue[700]!, width: 2),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              style: const TextStyle(fontSize: 18),
            ),
            
            const SizedBox(height: 25),
            
            // Submit Button
            ElevatedButton.icon(
              onPressed: _isSendingEmail ? null : _sendEmail,
              icon: _isSendingEmail
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send, size: 24),
              label: Text(
                _isSendingEmail ? 'Sending...' : 'Send Email',
                style: const TextStyle(fontSize: 20),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isSmtpConfigured ? Colors.blue[700] : Colors.grey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 5,
              ),
            ),
            
            const SizedBox(height: 25),
            
            // Status Info
            if (!isSmtpConfigured)
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.orange[700], size: 20),
                        const SizedBox(width: 10),
                        Text(
                          'Setup Required',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Update preview_print_page.dart (line 30-32):\n'
                      '1. SMTP_EMAIL = "your_email@gmail.com"\n'
                      '2. SMTP_PASSWORD = "app password"\n\n'
                      'Get App Password:\n'
                      'myaccount.google.com/apppasswords',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[800],
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'SMTP Configured ✓\nSending from: $SMTP_EMAIL',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return ElevatedButton.icon(
      onPressed: _isProcessing ? null : onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: 30,
          vertical: 20,
        ),
        textStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
    );
  }
}