import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/mode_recipe_graph.dart';

/// Decoded copies of design/examples/mode_recipe.json and
/// design/examples/operation_registry.json (no file I/O or JSON parsing here).
Map<String, dynamic> _recipe() => <String, dynamic>{
  'id': 'text-translation',
  'title_key': 'mode.text',
  'nodes': <dynamic>[
    <String, dynamic>{
      'id': 'input',
      'operation': 'input.text',
      'role': 'source',
      'inputs': <String, dynamic>{},
      'outputs': <String, dynamic>{'text': 'text'},
      'required_capabilities': <dynamic>[],
      'parameters': <String, dynamic>{},
    },
    <String, dynamic>{
      'id': 'translate',
      'operation': 'translation.text',
      'role': 'processor',
      'inputs': <String, dynamic>{'text': 'text'},
      'outputs': <String, dynamic>{'result': 'translations'},
      'required_capabilities': <dynamic>['translation.text'],
      'parameters': <String, dynamic>{},
    },
    <String, dynamic>{
      'id': 'show',
      'operation': 'output.translations',
      'role': 'sink',
      'inputs': <String, dynamic>{'result': 'translations'},
      'outputs': <String, dynamic>{},
      'required_capabilities': <dynamic>[],
      'parameters': <String, dynamic>{},
    },
  ],
  'edges': <dynamic>[
    <String, dynamic>{
      'from_node': 'input',
      'from_port': 'text',
      'to_node': 'translate',
      'to_port': 'text',
    },
    <String, dynamic>{
      'from_node': 'translate',
      'from_port': 'result',
      'to_node': 'show',
      'to_port': 'result',
    },
  ],
  'view': 'parallel-text',
  'target_policy': 'selected_languages',
  'permissions': <dynamic>[],
  'resource_profile': 'interactive',
  'processing_location': 'device',
  'retention': 'session',
};

Map<String, dynamic> _registry() => <String, dynamic>{
  'input.text': <String, dynamic>{
    'role': 'source',
    'inputs': <String, dynamic>{},
    'outputs': <String, dynamic>{'text': 'text'},
    'required_capabilities': <dynamic>[],
    'permissions': <dynamic>[],
    'parameters_schema': <String, dynamic>{},
  },
  'translation.text': <String, dynamic>{
    'role': 'processor',
    'inputs': <String, dynamic>{'text': 'text'},
    'outputs': <String, dynamic>{'result': 'translations'},
    'required_capabilities': <dynamic>['translation.text'],
    'permissions': <dynamic>[],
    'parameters_schema': <String, dynamic>{},
  },
  'output.translations': <String, dynamic>{
    'role': 'sink',
    'inputs': <String, dynamic>{'result': 'translations'},
    'outputs': <String, dynamic>{},
    'required_capabilities': <dynamic>[],
    'permissions': <dynamic>[],
    'parameters_schema': <String, dynamic>{},
  },
};

Map<String, dynamic> _node(Map<String, dynamic> recipe, int index) =>
    (recipe['nodes'] as List<dynamic>)[index] as Map<String, dynamic>;

Map<String, dynamic> _edge(Map<String, dynamic> recipe, int index) =>
    (recipe['edges'] as List<dynamic>)[index] as Map<String, dynamic>;

ModeRecipeValidation _check(
  Map<String, dynamic> recipe, {
  Object? registry,
  Set<String> capabilities = const {'translation.text'},
}) => validateModeRecipe(recipe, registry ?? _registry(), capabilities);

Set<ModeRecipeViolation> _kinds(ModeRecipeValidation result) =>
    result.issues.map((issue) => issue.kind).toSet();

void main() {
  test('example recipe is valid, requires one capability and has a topological order', () {
    final result = _check(_recipe());
    expect(result.valid, isTrue);
    expect(result.issues, isEmpty);
    expect(result.requiredCapabilities, {'translation.text'});
    expect(result.executionOrder, ['input', 'translate', 'show']);
  });

  test('results are deterministic and immutable', () {
    final recipe = _recipe();
    final first = _check(recipe);
    final second = _check(recipe);
    expect(first.issues, second.issues);
    expect(first.executionOrder, second.executionOrder);
    expect(
      () => first.issues.add(
        const ModeRecipeIssue(ModeRecipeViolation.invalidShape, 'x'),
      ),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      () => first.executionOrder.add('x'),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('duplicate node id is rejected', () {
    final recipe = _recipe();
    final duplicate = Map<String, dynamic>.from(_node(recipe, 0));
    (recipe['nodes'] as List<dynamic>).add(duplicate);
    expect(
      _kinds(_check(recipe)),
      contains(ModeRecipeViolation.duplicateNodeId),
    );
  });

  test('unknown operation is rejected', () {
    final recipe = _recipe();
    _node(recipe, 1)['operation'] = 'translation.missing';
    expect(
      _kinds(_check(recipe)),
      contains(ModeRecipeViolation.unknownOperation),
    );
  });

  test('role mismatch is rejected', () {
    final recipe = _recipe();
    _node(recipe, 1)['role'] = 'sink';
    expect(_kinds(_check(recipe)), contains(ModeRecipeViolation.roleMismatch));
  });

  test('input port mismatch is rejected', () {
    final recipe = _recipe();
    _node(recipe, 1)['inputs'] = <String, dynamic>{'other': 'text'};
    expect(
      _kinds(_check(recipe)),
      contains(ModeRecipeViolation.inputPortMismatch),
    );
  });

  test('input type mismatch is rejected', () {
    final recipe = _recipe();
    (_node(recipe, 1)['inputs'] as Map<String, dynamic>)['text'] = 'string';
    expect(
      _kinds(_check(recipe)),
      contains(ModeRecipeViolation.inputTypeMismatch),
    );
  });

  test('output port mismatch is rejected', () {
    final recipe = _recipe();
    _node(recipe, 0)['outputs'] = <String, dynamic>{'body': 'text'};
    expect(
      _kinds(_check(recipe)),
      contains(ModeRecipeViolation.outputPortMismatch),
    );
  });

  test('output type mismatch is rejected', () {
    final recipe = _recipe();
    (_node(recipe, 0)['outputs'] as Map<String, dynamic>)['text'] = 'bytes';
    expect(
      _kinds(_check(recipe)),
      contains(ModeRecipeViolation.outputTypeMismatch),
    );
  });

  test(
    'permission required by a registered operation must be in the recipe',
    () {
      final registry = _registry();
      ((registry['translation.text'] as Map<String, dynamic>)['permissions']
              as List<dynamic>)
          .add('io.clipboard');
      expect(
        _kinds(_check(_recipe(), registry: registry)),
        contains(ModeRecipeViolation.missingPermission),
      );
    },
  );

  test('node capability mismatch against registry is rejected', () {
    final recipe = _recipe();
    _node(recipe, 1)['required_capabilities'] = <dynamic>[];
    expect(
      _kinds(_check(recipe)),
      contains(ModeRecipeViolation.nodeCapabilityMismatch),
    );
  });

  test('undeclared capability is rejected but still reported as required', () {
    final result = _check(_recipe(), capabilities: const <String>{});
    expect(_kinds(result), contains(ModeRecipeViolation.undeclaredCapability));
    expect(result.requiredCapabilities, {'translation.text'});
  });

  test('repeated registry capability and permission tokens agree with Python set semantics', () {
    final registry = _registry();
    final operation = registry['translation.text'] as Map<String, dynamic>;
    operation['required_capabilities'] = <dynamic>[
      'translation.text',
      'translation.text',
    ];
    operation['permissions'] = <dynamic>['io.clipboard', 'io.clipboard'];
    final recipe = _recipe();
    (recipe['permissions'] as List<dynamic>).add('io.clipboard');
    final result = _check(recipe, registry: registry);
    expect(result.valid, isTrue, reason: result.issues.toString());
    expect(result.requiredCapabilities, {'translation.text'});

    final duplicateRecipe = _recipe();
    _node(duplicateRecipe, 1)['required_capabilities'] = <dynamic>[
      'translation.text',
      'translation.text',
    ];
    expect(
      _kinds(_check(duplicateRecipe)),
      contains(ModeRecipeViolation.invalidShape),
    );
  });

  test('edge to unknown node is rejected', () {
    final recipe = _recipe();
    _edge(recipe, 1)['to_node'] = 'missing';
    expect(
      _kinds(_check(recipe)),
      contains(ModeRecipeViolation.edgeUnknownNode),
    );
  });

  test('edge to unknown port is rejected', () {
    final recipe = _recipe();
    _edge(recipe, 0)['from_port'] = 'body';
    expect(
      _kinds(_check(recipe)),
      contains(ModeRecipeViolation.edgeUnknownPort),
    );
  });

  test('edge with mismatched endpoint types is rejected', () {
    final recipe = _recipe();
    final registry = _registry();
    (_node(recipe, 0)['outputs'] as Map<String, dynamic>)['text'] = 'bytes';
    ((registry['input.text'] as Map<String, dynamic>)['outputs']
            as Map<String, dynamic>)['text'] =
        'bytes';
    expect(
      _kinds(_check(recipe, registry: registry)),
      contains(ModeRecipeViolation.edgeTypeMismatch),
    );
  });

  test('two edges into one input pin are rejected', () {
    final recipe = _recipe();
    (recipe['nodes'] as List<dynamic>).add(<String, dynamic>{
      'id': 'input2',
      'operation': 'input.text',
      'role': 'source',
      'inputs': <String, dynamic>{},
      'outputs': <String, dynamic>{'text': 'text'},
      'required_capabilities': <dynamic>[],
      'parameters': <String, dynamic>{},
    });
    (recipe['edges'] as List<dynamic>).add(<String, dynamic>{
      'from_node': 'input2',
      'from_port': 'text',
      'to_node': 'translate',
      'to_port': 'text',
    });
    expect(
      _kinds(_check(recipe)),
      contains(ModeRecipeViolation.duplicateInputEdge),
    );
  });

  test('a cycle is rejected', () {
    final recipe = _recipe();
    (recipe['edges'] as List<dynamic>).add(<String, dynamic>{
      'from_node': 'translate',
      'from_port': 'result',
      'to_node': 'translate',
      'to_port': 'text',
    });
    expect(_kinds(_check(recipe)), contains(ModeRecipeViolation.cyclicGraph));
  });

  test('a node outside the source-to-sink flow is rejected', () {
    final recipe = _recipe();
    (recipe['nodes'] as List<dynamic>).add(<String, dynamic>{
      'id': 'extra',
      'operation': 'input.text',
      'role': 'source',
      'inputs': <String, dynamic>{},
      'outputs': <String, dynamic>{'text': 'text'},
      'required_capabilities': <dynamic>[],
      'parameters': <String, dynamic>{},
    });
    expect(
      _kinds(_check(recipe)),
      contains(ModeRecipeViolation.disconnectedNode),
    );
  });

  test('a recipe without a sink is rejected', () {
    final recipe = _recipe();
    _node(recipe, 2)['role'] = 'processor';
    expect(_kinds(_check(recipe)), contains(ModeRecipeViolation.missingSink));
  });

  test('an unconnected sink input is rejected', () {
    final recipe = _recipe();
    (recipe['edges'] as List<dynamic>).removeAt(1);
    expect(
      _kinds(_check(recipe)),
      contains(ModeRecipeViolation.unconnectedSinkInput),
    );
  });

  test('malformed recipe fields are issues, not exceptions', () {
    for (final recipe in <Object?>[null, 'not a recipe', <String, dynamic>{}]) {
      expect(
        validateModeRecipe(recipe, _registry(), const {
          'translation.text',
        }).valid,
        isFalse,
      );
    }
    final missing = _recipe()..remove('view');
    expect(
      _check(missing).issues.map((issue) => issue.path),
      contains('recipe.view'),
    );
    final token = _recipe()..['id'] = 'Bad ID';
    expect(
      _check(token).issues.map((issue) => issue.path),
      contains('recipe.id'),
    );
    final extra = _recipe()..['queue_policy'] = 'fifo';
    expect(
      _check(extra).issues.map((issue) => issue.path),
      contains('recipe.queue_policy'),
    );
    final shortNodes = _recipe()..['nodes'] = <dynamic>[_node(_recipe(), 0)];
    expect(_check(shortNodes).issues, isNotEmpty);
    final noEdges = _recipe()..['edges'] = <dynamic>[];
    expect(_check(noEdges).issues, isNotEmpty);
  });

  test('malformed registry fields and duplicate edges are issues', () {
    final registry = _registry();
    (registry['translation.text'] as Map<String, dynamic>).remove(
      'permissions',
    );
    expect(
      _check(_recipe(), registry: registry).issues.map((issue) => issue.path),
      contains('registry[1].permissions'),
    );
    final recipe = _recipe();
    (recipe['edges'] as List<dynamic>).add(
      Map<String, dynamic>.from(_edge(recipe, 0)),
    );
    expect(_kinds(_check(recipe)), contains(ModeRecipeViolation.invalidShape));
  });

  test('issue paths never echo arbitrary caller values', () {
    final recipe = _recipe()..['id'] = 'Private User Data Value';
    final issues = _check(recipe).issues;
    expect(issues, isNotEmpty);
    expect(issues.map((issue) => issue.path), contains('recipe.id'));
    expect(
      issues.any((issue) => issue.path.contains('Private User Data Value')),
      isFalse,
    );
  });
  test('dotted node and port names are keyed without collision', () {
    final registry = <String, dynamic>{
      'op.src': <String, dynamic>{
        'role': 'source',
        'inputs': <String, dynamic>{},
        'outputs': <String, dynamic>{'text': 'text'},
        'required_capabilities': <dynamic>[],
        'permissions': <dynamic>[],
        'parameters_schema': <String, dynamic>{},
      },
      'op.sink1': <String, dynamic>{
        'role': 'sink',
        'inputs': <String, dynamic>{'c': 'text'},
        'outputs': <String, dynamic>{},
        'required_capabilities': <dynamic>[],
        'permissions': <dynamic>[],
        'parameters_schema': <String, dynamic>{},
      },
      'op.sink2': <String, dynamic>{
        'role': 'sink',
        'inputs': <String, dynamic>{'b.c': 'text'},
        'outputs': <String, dynamic>{},
        'required_capabilities': <dynamic>[],
        'permissions': <dynamic>[],
        'parameters_schema': <String, dynamic>{},
      },
    };
    final recipe = <String, dynamic>{
      'id': 'dotted.valid',
      'title_key': 'mode.text',
      'nodes': <dynamic>[
        <String, dynamic>{
          'id': 'src1',
          'operation': 'op.src',
          'role': 'source',
          'inputs': <String, dynamic>{},
          'outputs': <String, dynamic>{'text': 'text'},
          'required_capabilities': <dynamic>[],
          'parameters': <String, dynamic>{},
        },
        <String, dynamic>{
          'id': 'src2',
          'operation': 'op.src',
          'role': 'source',
          'inputs': <String, dynamic>{},
          'outputs': <String, dynamic>{'text': 'text'},
          'required_capabilities': <dynamic>[],
          'parameters': <String, dynamic>{},
        },
        <String, dynamic>{
          'id': 'a.b',
          'operation': 'op.sink1',
          'role': 'sink',
          'inputs': <String, dynamic>{'c': 'text'},
          'outputs': <String, dynamic>{},
          'required_capabilities': <dynamic>[],
          'parameters': <String, dynamic>{},
        },
        <String, dynamic>{
          'id': 'a',
          'operation': 'op.sink2',
          'role': 'sink',
          'inputs': <String, dynamic>{'b.c': 'text'},
          'outputs': <String, dynamic>{},
          'required_capabilities': <dynamic>[],
          'parameters': <String, dynamic>{},
        },
      ],
      'edges': <dynamic>[
        <String, dynamic>{
          'from_node': 'src1',
          'from_port': 'text',
          'to_node': 'a.b',
          'to_port': 'c',
        },
        <String, dynamic>{
          'from_node': 'src2',
          'from_port': 'text',
          'to_node': 'a',
          'to_port': 'b.c',
        },
      ],
      'view': 'parallel-text',
      'target_policy': 'selected_languages',
      'permissions': <dynamic>[],
      'resource_profile': 'interactive',
      'processing_location': 'device',
      'retention': 'session',
    };
    final result = validateModeRecipe(recipe, registry, const {});
    expect(result.valid, isTrue);
    expect(result.issues, isEmpty);
    expect(
      _kinds(result),
      isNot(contains(ModeRecipeViolation.duplicateInputEdge)),
    );
  });

  test('dotted collision does not mask an unwired sink input', () {
    final registry = <String, dynamic>{
      'op.src': <String, dynamic>{
        'role': 'source',
        'inputs': <String, dynamic>{},
        'outputs': <String, dynamic>{'text': 'text'},
        'required_capabilities': <dynamic>[],
        'permissions': <dynamic>[],
        'parameters_schema': <String, dynamic>{},
      },
      'op.other': <String, dynamic>{
        'role': 'sink',
        'inputs': <String, dynamic>{'c': 'text'},
        'outputs': <String, dynamic>{},
        'required_capabilities': <dynamic>[],
        'permissions': <dynamic>[],
        'parameters_schema': <String, dynamic>{},
      },
      'op.sink': <String, dynamic>{
        'role': 'sink',
        'inputs': <String, dynamic>{'b.c': 'text', 'x': 'text'},
        'outputs': <String, dynamic>{},
        'required_capabilities': <dynamic>[],
        'permissions': <dynamic>[],
        'parameters_schema': <String, dynamic>{},
      },
    };
    final recipe = <String, dynamic>{
      'id': 'dotted.masked',
      'title_key': 'mode.text',
      'nodes': <dynamic>[
        <String, dynamic>{
          'id': 'src1',
          'operation': 'op.src',
          'role': 'source',
          'inputs': <String, dynamic>{},
          'outputs': <String, dynamic>{'text': 'text'},
          'required_capabilities': <dynamic>[],
          'parameters': <String, dynamic>{},
        },
        <String, dynamic>{
          'id': 'src2',
          'operation': 'op.src',
          'role': 'source',
          'inputs': <String, dynamic>{},
          'outputs': <String, dynamic>{'text': 'text'},
          'required_capabilities': <dynamic>[],
          'parameters': <String, dynamic>{},
        },
        <String, dynamic>{
          'id': 'a.b',
          'operation': 'op.other',
          'role': 'sink',
          'inputs': <String, dynamic>{'c': 'text'},
          'outputs': <String, dynamic>{},
          'required_capabilities': <dynamic>[],
          'parameters': <String, dynamic>{},
        },
        <String, dynamic>{
          'id': 'a',
          'operation': 'op.sink',
          'role': 'sink',
          'inputs': <String, dynamic>{'b.c': 'text', 'x': 'text'},
          'outputs': <String, dynamic>{},
          'required_capabilities': <dynamic>[],
          'parameters': <String, dynamic>{},
        },
      ],
      'edges': <dynamic>[
        <String, dynamic>{
          'from_node': 'src1',
          'from_port': 'text',
          'to_node': 'a.b',
          'to_port': 'c',
        },
        <String, dynamic>{
          'from_node': 'src2',
          'from_port': 'text',
          'to_node': 'a',
          'to_port': 'x',
        },
      ],
      'view': 'parallel-text',
      'target_policy': 'selected_languages',
      'permissions': <dynamic>[],
      'resource_profile': 'interactive',
      'processing_location': 'device',
      'retention': 'session',
    };
    final result = validateModeRecipe(recipe, registry, const {});
    expect(result.valid, isFalse);
    expect(_kinds(result), contains(ModeRecipeViolation.unconnectedSinkInput));
  });

  test('extra recipe permission is rejected', () {
    final recipe = _recipe()..['permissions'] = <dynamic>['io.clipboard'];
    final result = _check(recipe);
    expect(result.valid, isFalse);
    expect(_kinds(result), contains(ModeRecipeViolation.extraPermission));
    expect(result.issues.map((issue) => issue.path), contains('permissions'));
    expect(
      result.issues.any((issue) => issue.path.contains('io.clipboard')),
      isFalse,
    );
  });

  test('missing recipe permission is rejected under exact scope', () {
    final registry = _registry();
    ((registry['translation.text'] as Map<String, dynamic>)['permissions']
            as List<dynamic>)
        .add('io.clipboard');
    final result = _check(_recipe(), registry: registry);
    expect(result.valid, isFalse);
    expect(_kinds(result), contains(ModeRecipeViolation.missingPermission));
  });

  test('unexpected parameter is rejected', () {
    final registry = _registry();
    (registry['translation.text']
        as Map<String, dynamic>)['parameters_schema'] = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <dynamic>[],
      'additionalProperties': false,
    };
    final recipe = _recipe();
    (_node(recipe, 1)['parameters'] as Map<String, dynamic>)['secret'] = 'x';
    final result = _check(recipe, registry: registry);
    expect(result.valid, isFalse);
    expect(_kinds(result), contains(ModeRecipeViolation.unexpectedParameter));
    expect(
      result.issues.any((issue) => issue.path.contains('secret')),
      isFalse,
    );
    expect(result.issues.any((issue) => issue.path.contains('x')), isFalse);
  });

  test('parameter with wrong type is rejected', () {
    final registry = _registry();
    (registry['translation.text']
        as Map<String, dynamic>)['parameters_schema'] = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'count': <String, dynamic>{'type': 'integer'},
      },
      'required': <dynamic>[],
      'additionalProperties': false,
    };
    final recipe = _recipe();
    (_node(recipe, 1)['parameters'] as Map<String, dynamic>)['count'] =
        'not-an-int';
    final result = _check(recipe, registry: registry);
    expect(result.valid, isFalse);
    expect(_kinds(result), contains(ModeRecipeViolation.parameterTypeMismatch));
  });

  test('integral double is a valid integer parameter', () {
    final registry = _registry();
    (registry['translation.text']
        as Map<String, dynamic>)['parameters_schema'] = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'count': <String, dynamic>{'type': 'integer'},
      },
      'required': <dynamic>[],
      'additionalProperties': false,
    };
    final integral = _recipe();
    (_node(integral, 1)['parameters'] as Map<String, dynamic>)['count'] = 1.0;
    final accepted = _check(integral, registry: registry);
    expect(accepted.valid, isTrue, reason: accepted.issues.toString());

    final large = _recipe();
    (_node(large, 1)['parameters'] as Map<String, dynamic>)['count'] = 1e20;
    final largeResult = _check(large, registry: registry);
    expect(largeResult.valid, isTrue, reason: largeResult.issues.toString());

    final fractional = _recipe();
    (_node(fractional, 1)['parameters'] as Map<String, dynamic>)['count'] = 1.5;
    final rejected = _check(fractional, registry: registry);
    expect(
      _kinds(rejected),
      contains(ModeRecipeViolation.parameterTypeMismatch),
    );
  });

  test('missing required parameter is rejected', () {
    final registry = _registry();
    (registry['translation.text']
        as Map<String, dynamic>)['parameters_schema'] = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'mode': <String, dynamic>{'type': 'string'},
      },
      'required': <dynamic>['mode'],
      'additionalProperties': false,
    };
    final result = _check(_recipe(), registry: registry);
    expect(result.valid, isFalse);
    expect(_kinds(result), contains(ModeRecipeViolation.missingParameter));
  });

  test('every declared processor input must be wired', () {
    final recipe = _recipe();
    (recipe['edges'] as List<dynamic>).removeAt(0);
    final result = _check(recipe);
    expect(result.valid, isFalse);
    expect(_kinds(result), contains(ModeRecipeViolation.unconnectedInput));
  });

  test('missing source is rejected', () {
    final recipe = _recipe();
    final registry = _registry();
    _node(recipe, 0)['role'] = 'processor';
    (registry['input.text'] as Map<String, dynamic>)['role'] = 'processor';
    final result = _check(recipe, registry: registry);
    expect(result.valid, isFalse);
    expect(_kinds(result), contains(ModeRecipeViolation.missingSource));
  });

  test('unsupported parameter schema is rejected', () {
    final registry = _registry();
    (registry['translation.text']
        as Map<String, dynamic>)['parameters_schema'] = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{},
      'x-unknown': true,
    };
    final result = _check(_recipe(), registry: registry);
    expect(result.valid, isFalse);
    expect(
      _kinds(result),
      contains(ModeRecipeViolation.unsupportedParameterSchema),
    );
  });
}
