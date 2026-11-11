import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/models.dart';
import 'package:agentphone/domain/server_gateway.dart' show ProductException;
import 'package:agentphone/paseo/gateway.dart';
import 'package:agentphone/paseo/mappers.dart';

void main() {
  test('pictures go to the agent as base64 with their type', () {
    final images = paseoImages(const [
      PromptAttachment(
        mime: 'image/png',
        filename: 'shot.png',
        url: 'data:image/png;base64,iVBORw0KGgo=',
      ),
    ]);
    expect(images, [
      {'data': 'iVBORw0KGgo=', 'mimeType': 'image/png'},
    ]);
  });

  test('other files are refused in words', () {
    expect(
      () => paseoImages(const [
        PromptAttachment(
          mime: 'application/pdf',
          filename: 'plan.pdf',
          url: 'data:application/pdf;base64,JVBERi0=',
        ),
      ]),
      throwsA(
        isA<ProductException>().having(
          (e) => e.message,
          'message',
          contains('takes pictures only'),
        ),
      ),
    );
  });

  test('agents on this phone take pictures, not other files', () {
    expect(paseoServerCapabilities.promptAttachments, isTrue);
    expect(paseoServerCapabilities.promptImagesOnly, isTrue);
  });

  // JPEG signature (FF D8 FF E0) under a ".png" name: what a picker gives when
  // the file name and the bytes disagree.
  const jpegData = '/9j/4AAQSkZJRgABAQ==';

  test('the type sent is the one the bytes are, not the file name', () {
    final images = paseoImages(const [
      PromptAttachment(
        mime: 'image/png',
        filename: 'shot.png',
        url: 'data:image/png;base64,$jpegData',
      ),
    ]);
    expect(images, [
      {'data': jpegData, 'mimeType': 'image/jpeg'},
    ]);
  });

  test('a picture type Claude does not take is refused in words', () {
    expect(
      () => paseoImages(const [
        PromptAttachment(
          mime: 'image/heic',
          filename: 'shot.heic',
          url: 'data:image/heic;base64,AAAAGGZ0eXBoZWlj',
        ),
      ]),
      throwsA(
        isA<ProductException>().having(
          (e) => e.message,
          'message',
          contains('PNG, JPEG, GIF or WebP'),
        ),
      ),
    );
  });
}
