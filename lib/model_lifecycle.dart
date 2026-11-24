/// Model states of design §10.3, in the order of the import-and-use flow of
/// §7.2: a candidate is selected, terms are reviewed and consented, content is
/// acquired and inspected, then the model is registered, loaded and becomes
/// available. A released model waits before deletion.
enum ModelState {
  candidate,
  awaitingConsent,
  acquiring,
  inspecting,
  installed,
  loading,
  available,
  releasing,
  pendingDeletion;

  /// Whether this state ends the lifecycle. No transition leaves a terminal
  /// state; a model in a terminal state is reported only, never changed here.
  bool get isTerminal => this == ModelState.pendingDeletion;
}

/// Classification of a refused lifecycle operation. Deliberately carries no
/// path, provider, digest, content, engine or network detail.
enum ModelLifecycleFailure { invalidTransition }

/// A refused transition. [from] and [attempted] name only a state and the
/// caller-supplied operation label, never an identity, content or external
/// identifier.
class ModelLifecycleException implements Exception {
  const ModelLifecycleException(this.failure, this.from, this.attempted);

  final ModelLifecycleFailure failure;
  final ModelState from;
  final String attempted;

  @override
  String toString() =>
      'ModelLifecycleException(${failure.name}: $attempted from ${from.name})';
}

/// In-memory lifecycle state machine for one model identity (design §10.3).
///
/// This reports the reported status of a user-managed model as it moves through
/// selection, consent, acquisition, inspection, registration, load, use,
/// release and pending deletion. It is a state machine only: it never reads a
/// file, invokes an engine, uses networking or persistence, wires any UI,
/// deletes bytes or cancels jobs. Format, signature, provenance and content
/// checks belong to manifest inspection and the ModelRegistry install path;
/// actual reference-safe removal belongs to ModelRegistry.remove and job
/// pinning to JobLifecycle. Offline operations (re-consent, deletion) require
/// the released [ModelState.installed] state, so a loaded model must first be
/// released. A changed-terms re-consent that is declined or fails returns an
/// already-installed model to [ModelState.installed], keeping [requestDeletion]
/// and [requestConsent] reachable; only a never-registered candidate is
/// discarded. Such a fallback keeps the registered bytes but is not loadable:
/// [beginLoad] fails closed until a full consent, acquisition and inspection
/// cycle succeeds again. No state here is a support, availability or quality
/// claim.
class ModelLifecycle {
  ModelLifecycle(this.manifestDigest);

  /// Opaque identity label for the model this lifecycle tracks. It is stored
  /// only to be reported back and is not itself a verification, availability
  /// or quality claim; its format and provenance are established elsewhere.
  final String manifestDigest;

  ModelState _state = ModelState.candidate;

  /// Whether content has passed inspection and is registered in the management
  /// area. This stays true across a changed-terms re-consent cycle so a decline
  /// or a failed re-acquisition/re-inspection returns the model to
  /// [ModelState.installed] (still registered, still deletable) rather than
  /// discarding it as a never-registered candidate.
  bool _registered = false;

  /// Whether current consent has passed acquisition and inspection. A consent
  /// cycle revokes this; registration alone never authorizes a load after
  /// changed terms or a failed or declined re-consent.
  bool _loadEligible = false;

  ModelState get state => _state;

  bool get isTerminal => _state.isTerminal;

  /// Present the terms and request explicit consent. Starting a cycle revokes
  /// load eligibility until acquisition and inspection succeed again.
  void requestConsent() {
    _transition(
      ModelState.awaitingConsent,
      'requestConsent',
      const <ModelState>{ModelState.candidate, ModelState.installed},
    );
    _loadEligible = false;
  }

  /// Explicit consent was granted; acquisition or local import may begin.
  void grantConsent() => _transition(
    ModelState.acquiring,
    'grantConsent',
    const <ModelState>{ModelState.awaitingConsent},
  );

  /// Consent was declined. A never-registered candidate is discarded; an
  /// already-installed model stays installed (registered, still deletable).
  void declineConsent() => _transition(
    _registered ? ModelState.installed : ModelState.candidate,
    'declineConsent',
    const <ModelState>{ModelState.awaitingConsent},
  );

  /// Acquisition or local import completed; inspection may begin.
  void acquisitionSucceeded() => _transition(
    ModelState.inspecting,
    'acquisitionSucceeded',
    const <ModelState>{ModelState.acquiring},
  );

  /// Acquisition was interrupted or failed. A never-registered candidate is
  /// discarded; an already-installed model stays installed and deletable.
  void acquisitionFailed() => _transition(
    _registered ? ModelState.installed : ModelState.candidate,
    'acquisitionFailed',
    const <ModelState>{ModelState.acquiring},
  );

  /// Inspection passed; the model is registered as installed.
  void inspectionSucceeded() {
    _transition(ModelState.installed, 'inspectionSucceeded', const <ModelState>{
      ModelState.inspecting,
    });
    _registered = true;
    _loadEligible = true;
  }

  /// Inspection rejected the content. A never-registered candidate is
  /// discarded; an already-installed model stays installed and deletable.
  void inspectionFailed() => _transition(
    _registered ? ModelState.installed : ModelState.candidate,
    'inspectionFailed',
    const <ModelState>{ModelState.inspecting},
  );

  /// Changed terms or revocation require the conditions to be presented and
  /// consent obtained again. The model must be released (installed) first.
  void termsChanged() {
    _transition(ModelState.awaitingConsent, 'termsChanged', const <ModelState>{
      ModelState.installed,
    });
    _loadEligible = false;
  }

  /// Begin loading the installed model into the runtime. A new or changed
  /// consent must pass acquisition and inspection again before a load.
  void beginLoad() {
    if (_state == ModelState.installed && !_loadEligible) {
      throw ModelLifecycleException(
        ModelLifecycleFailure.invalidTransition,
        _state,
        'beginLoad',
      );
    }
    _transition(ModelState.loading, 'beginLoad', const <ModelState>{
      ModelState.installed,
    });
  }

  /// Load succeeded; the model is available for jobs.
  void loadSucceeded() => _transition(
    ModelState.available,
    'loadSucceeded',
    const <ModelState>{ModelState.loading},
  );

  /// Load failed; the model stays installed and can be reloaded.
  void loadFailed() => _transition(
    ModelState.installed,
    'loadFailed',
    const <ModelState>{ModelState.loading},
  );

  /// Begin releasing the loaded model so it can be reloaded or deleted.
  void beginRelease() => _transition(
    ModelState.releasing,
    'beginRelease',
    const <ModelState>{ModelState.available},
  );

  /// Release completed; the model is installed but not loaded.
  void releaseSucceeded() => _transition(
    ModelState.installed,
    'releaseSucceeded',
    const <ModelState>{ModelState.releasing},
  );

  /// Deletion was requested for a released model. This only reports the
  /// terminal state; it removes no bytes and refuses to bypass release.
  void requestDeletion() => _transition(
    ModelState.pendingDeletion,
    'requestDeletion',
    const <ModelState>{ModelState.installed},
  );

  void _transition(ModelState next, String op, Set<ModelState> allowed) {
    if (!allowed.contains(_state)) {
      throw ModelLifecycleException(
        ModelLifecycleFailure.invalidTransition,
        _state,
        op,
      );
    }
    _state = next;
  }
}
