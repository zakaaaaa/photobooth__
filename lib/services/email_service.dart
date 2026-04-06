import 'package:photobooth_app/services/app_logger.dart';

import 'dart:io';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class EmailService {
  // ⚠️ GANTI DENGAN EMAIL & APP PASSWORD ANDA ⚠️
  final String _username = 'zakakurnia0@gmail.com';
  final String _password = 'sgbo kslt altd hlvl';

  // UBAH PARAMETER KE List<String> filePaths
  Future<bool> sendEmailWithAttachments(
      String recipientEmail, List<String> filePaths) async {
    final smtpServer = gmail(_username, _password);

    final message = Message()
      ..from = Address(_username, 'ITA Optical Photobooth')
      ..recipients.add(recipientEmail)
      ..subject = 'Halo, terimakasih sudah berfoto dengan kami 📸'
      ..text =
          'Ayo posting di instagram stories kamu dan tag kami @eyesonkanawa @optik_ita @optik.indojaya 🎉';

    // LOOPING UNTUK MENAMBAHKAN SEMUA FILE
    for (String path in filePaths) {
      message.attachments.add(FileAttachment(File(path)));
    }

    try {
      final sendReport = await send(message, smtpServer);
      AppLogger.debug('Message sent: $sendReport');
      return true;
    } catch (e) {
      AppLogger.debug('Message not sent.\n$e');
      return false;
    }
  }
}
