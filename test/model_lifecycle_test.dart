import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/model_lifecycle.dart';

const String id =
    'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';

void expectInvalidTransition(
  ModelLifecycleFailure failure,
  void Function() action,
) {
  expect(
    action,
    throwsA(
      isA<ModelLifecycleException>().having(
        (e) => e.failure,
        'failure',
        failure,
      ),
    ),
  );
}

/// Advance a fresh lifecycle to the installed (released) state.
ModelLifecycle installedModel() => ModelLifecycle(id)
  ..requestConsent()
  ..grantConsent()
  ..acquisitionSucceeded()
  ..inspectionSucceeded();

// Design §10.3 states and §7.2 flow. That this module never reads a file,
// invokes an engine, uses networking/persistence or wires UI cannot be probed
// in pure Dart; it is enforced structurally: lib/model_lifecycle.dart has no
// imports at all. These tests exercise only the reported state transitions.
void main() {
  test('construction starts at candidate and keeps the opaque identity', () {
    final model = ModelLifecycle(id);
    expect(model.state, ModelState.candidate);
    expect(model.isTerminal, isFalse);
    expect(model.manifestDigest, id);
  });

  test('happy path moves through every forward state to deleted', () {
    final model = ModelLifecycle(id)
      ..requestConsent()
      ..grantConsent()
      ..acquisitionSucceeded()
      ..inspectionSucceeded()
      ..beginLoad()
      ..loadSucceeded()
      ..beginRelease()
      ..releaseSucceeded()
      ..requestDeletion();
    expect(model.state, ModelState.pendingDeletion);
    expect(model.isTerminal, isTrue);
  });

  test('each intermediate state is observable', () {
    final model = ModelLifecycle(id);
    model.requestConsent();
    expect(model.state, ModelState.awaitingConsent);
    model.grantConsent();
    expect(model.state, ModelState.acquiring);
    model.acquisitionSucceeded();
    expect(model.state, ModelState.inspecting);
    model.inspectionSucceeded();
    expect(model.state, ModelState.installed);
    model.beginLoad();
    expect(model.state, ModelState.loading);
    model.loadSucceeded();
    expect(model.state, ModelState.available);
    model.beginRelease();
    expect(model.state, ModelState.releasing);
  });

  test('consent decline discards the candidate', () {
    final model = ModelLifecycle(id)
      ..requestConsent()
      ..declineConsent();
    expect(model.state, ModelState.candidate);
  });

  test('interrupted acquisition discards the candidate', () {
    final model = ModelLifecycle(id)
      ..requestConsent()
      ..grantConsent()
      ..acquisitionFailed();
    expect(model.state, ModelState.candidate);
  });

  test('failed inspection discards the candidate', () {
    final model = ModelLifecycle(id)
      ..requestConsent()
      ..grantConsent()
      ..acquisitionSucceeded()
      ..inspectionFailed();
    expect(model.state, ModelState.candidate);
  });

  test('failed load stays installed and can be reloaded', () {
    final model = installedModel()
      ..beginLoad()
      ..loadFailed();
    expect(model.state, ModelState.installed);
    model
      ..beginLoad()
      ..loadSucceeded();
    expect(model.state, ModelState.available);
  });

  test('changed terms require fresh consent and full re-validation', () {
    final model = installedModel()..termsChanged();
    expect(model.state, ModelState.awaitingConsent);
    // Re-consent does not skip acquisition or inspection.
    expectInvalidTransition(
      ModelLifecycleFailure.invalidTransition,
      model.inspectionSucceeded,
    );
    model
      ..grantConsent()
      ..acquisitionSucceeded()
      ..inspectionSucceeded();
    expect(model.state, ModelState.installed);
  });

  test('re-consent requires the released state', () {
    final model = installedModel()
      ..beginLoad()
      ..loadSucceeded();
    expectInvalidTransition(
      ModelLifecycleFailure.invalidTransition,
      model.termsChanged,
    );
    expect(model.state, ModelState.available);
    model
      ..beginRelease()
      ..releaseSucceeded()
      ..termsChanged();
    expect(model.state, ModelState.awaitingConsent);
  });

  test('deletion is refused while loaded and allowed only after release', () {
    final model = installedModel()
      ..beginLoad()
      ..loadSucceeded();
    expectInvalidTransition(
      ModelLifecycleFailure.invalidTransition,
      model.requestDeletion,
    );
    expect(model.state, ModelState.available);
    model.beginRelease();
    expectInvalidTransition(
      ModelLifecycleFailure.invalidTransition,
      model.requestDeletion,
    );
    expect(model.state, ModelState.releasing);
    model
      ..releaseSucceeded()
      ..requestDeletion();
    expect(model.state, ModelState.pendingDeletion);
  });

  test('out-of-order transitions fail closed without changing state', () {
    final model = ModelLifecycle(id);
    expectInvalidTransition(
      ModelLifecycleFailure.invalidTransition,
      model.grantConsent,
    );
    expectInvalidTransition(
      ModelLifecycleFailure.invalidTransition,
      model.beginLoad,
    );
    expectInvalidTransition(
      ModelLifecycleFailure.invalidTransition,
      model.requestDeletion,
    );
    expect(model.state, ModelState.candidate);
  });

  test('leaving the terminal state fails closed', () {
    final model = installedModel()..requestDeletion();
    expectInvalidTransition(
      ModelLifecycleFailure.invalidTransition,
      model.requestConsent,
    );
    expectInvalidTransition(
      ModelLifecycleFailure.invalidTransition,
      model.beginLoad,
    );
    expectInvalidTransition(
      ModelLifecycleFailure.invalidTransition,
      model.requestDeletion,
    );
    expect(model.state, ModelState.pendingDeletion);
    expect(model.isTerminal, isTrue);
  });

  test('exception names only the failure, from-state and operation', () {
    final model = ModelLifecycle(id);
    try {
      model.loadSucceeded();
      fail('expected a refusal');
    } on ModelLifecycleException catch (e) {
      expect(e.failure, ModelLifecycleFailure.invalidTransition);
      expect(e.from, ModelState.candidate);
      expect(e.attempted, 'loadSucceeded');
      expect(
        e.toString(),
        'ModelLifecycleException(invalidTransition: loadSucceeded from candidate)',
      );
      expect(e.toString(), isNot(contains(id)));
    }
  });

  // Reviewer finding seq 55: an already-installed model whose changed terms
  // are declined (or whose re-consent re-acquisition/re-inspection fails) must
  // remain deletable; it is still registered, just not usable under new terms.
  test('declining re-consent keeps an installed model deletable', () {
    final model = installedModel()
      ..termsChanged()
      ..declineConsent();
    expect(model.state, ModelState.installed);
    expect(model.isTerminal, isFalse);
    model.requestDeletion();
    expect(model.state, ModelState.pendingDeletion);
  });

  test('failed re-acquisition after re-consent keeps the model deletable', () {
    final model = installedModel()
      ..termsChanged()
      ..grantConsent()
      ..acquisitionFailed();
    expect(model.state, ModelState.installed);
    model.requestDeletion();
    expect(model.state, ModelState.pendingDeletion);
  });

  test('failed re-inspection after re-consent keeps the model deletable', () {
    final model = installedModel()
      ..termsChanged()
      ..grantConsent()
      ..acquisitionSucceeded()
      ..inspectionFailed();
    expect(model.state, ModelState.installed);
    model.requestDeletion();
    expect(model.state, ModelState.pendingDeletion);
  });

  test('first-consent failures still discard an unregistered candidate', () {
    final declined = ModelLifecycle(id)
      ..requestConsent()
      ..declineConsent();
    expect(declined.state, ModelState.candidate);
    expectInvalidTransition(
      ModelLifecycleFailure.invalidTransition,
      declined.requestDeletion,
    );
    final failed = ModelLifecycle(id)
      ..requestConsent()
      ..grantConsent()
      ..acquisitionFailed();
    expect(failed.state, ModelState.candidate);
    expectInvalidTransition(
      ModelLifecycleFailure.invalidTransition,
      failed.requestDeletion,
    );
  });
}
