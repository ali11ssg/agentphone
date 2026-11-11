import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/product_repository.dart';

void main() {
  test('a repository without message deletion stays a bounded error', () async {
    final repository = _MinimalRepository();
    await expectLater(
      repository.deleteMessage(sessionID: 's', messageID: 'm'),
      throwsA(
        isA<ProductException>().having(
          (error) => error.toString(),
          'message',
          contains('Message deletion is unavailable'),
        ),
      ),
    );
  });
}

class _MinimalRepository extends ProductRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
