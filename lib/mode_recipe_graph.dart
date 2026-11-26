/// Developer-facing validation of a decoded mode recipe graph (design §15).
///
/// Pure in-memory data check: the inputs are already-decoded values, and this
/// library performs no I/O, JSON parsing, network or engine/model work and
/// depends on no Flutter widget. A valid result means the declared ports,
/// permissions, capabilities, parameters and connectivity are internally
/// consistent; it makes no claim about adoption, availability or output
/// quality and does not execute the recipe. Parameters are checked against
/// the registry's `parameters_schema` with a minimal fail-closed subset:
/// `type: 'object'`, `properties` with per-property `type` among
/// string/integer/number/boolean/object/array/null, `required` string list,
/// `additionalProperties` bool and `minProperties`/`maxProperties` ints.
/// Any other schema keyword yields [ModeRecipeViolation.unsupportedParameterSchema].
library;

/// Stable reason a recipe graph is rejected.
enum ModeRecipeViolation {
  /// A required field is absent or has the wrong basic shape/value.
  invalidShape,

  /// Two nodes declare the same id.
  duplicateNodeId,

  /// A node names an operation missing from the registry.
  unknownOperation,

  /// A node's role differs from its registered operation's role.
  roleMismatch,

  /// A node's input ports differ from the registered operation's.
  inputPortMismatch,

  /// A shared input port has a different declared type.
  inputTypeMismatch,

  /// A node's output ports differ from the registered operation's.
  outputPortMismatch,

  /// A shared output port has a different declared type.
  outputTypeMismatch,

  /// The recipe does not declare a permission required by an operation.
  missingPermission,

  /// Node and registry disagree on required capabilities.
  nodeCapabilityMismatch,

  /// A required capability is absent from the caller's declared set.
  undeclaredCapability,

  /// An edge names a node that does not exist.
  edgeUnknownNode,

  /// An edge names a port the endpoint node does not declare.
  edgeUnknownPort,

  /// Source output and destination input types differ.
  edgeTypeMismatch,

  /// Two edges feed the same destination input port.
  duplicateInputEdge,

  /// The directed graph contains a cycle (including a self-loop).
  cyclicGraph,

  /// A node is not on a path from any source to any sink.
  disconnectedNode,

  /// The recipe has no sink node.
  missingSink,

  /// A sink input port has no incoming edge.
  unconnectedSinkInput,

  /// The recipe declares a permission no used operation requires.
  extraPermission,

  /// A node declares a parameter not allowed by its operation schema.
  unexpectedParameter,

  /// A parameter required by the operation schema is absent.
  missingParameter,

  /// A parameter value has the wrong type for its operation schema.
  parameterTypeMismatch,

  /// The operation schema uses keywords outside the supported subset.
  unsupportedParameterSchema,

  /// A non-sink input port has no incoming edge.
  unconnectedInput,

  /// The recipe has no source node.
  missingSource,
}

/// One located reason for rejection. [path] names a schema location (for
/// example `nodes[1].inputs[text]`), never an arbitrary or user-supplied value.
class ModeRecipeIssue {
  const ModeRecipeIssue(this.kind, this.path);

  final ModeRecipeViolation kind;
  final String path;

  @override
  bool operator ==(Object other) =>
      other is ModeRecipeIssue && other.kind == kind && other.path == path;

  @override
  int get hashCode => Object.hash(kind, path);

  @override
  String toString() => '$kind at $path';
}

/// Immutable result of validating one recipe against one registry.
class ModeRecipeValidation {
  const ModeRecipeValidation._(
    this.issues,
    this.requiredCapabilities,
    this.executionOrder,
  );

  /// No issue was found.
  bool get valid => issues.isEmpty;

  /// All distinct issues, ordered by violation kind then path.
  final List<ModeRecipeIssue> issues;

  /// Union of the recipe's node capabilities, sorted for stable reporting.
  final Set<String> requiredCapabilities;

  /// Deterministic topological node ids, or empty unless [valid] is true.
  final List<String> executionOrder;
}

/// Validates [recipe] and [registry] as already-decoded values against
/// [declaredCapabilities]. Malformed input yields [ModeRecipeViolation.invalidShape]
/// issues instead of throwing; dependent checks are skipped in that case.
ModeRecipeValidation validateModeRecipe(
  Object? recipe,
  Object? registry,
  Set<String> declaredCapabilities,
) {
  final issues = <ModeRecipeIssue>[];
  final shape = _readRecipe(recipe, issues);
  final operations = _readRegistry(registry, issues);
  if (shape == null || operations == null || issues.isNotEmpty) {
    return _result(issues, const {}, const []);
  }

  final byId = <String, _Node>{};
  for (final node in shape.nodes) {
    if (byId.containsKey(node.id)) {
      issues.add(
        _issue(ModeRecipeViolation.duplicateNodeId, 'nodes[${node.index}].id'),
      );
    } else {
      byId[node.id] = node;
    }
  }
  final nodes = byId.values.toList();
  final capabilities = <String>{};
  final requiredPermissions = <String>{};

  for (final node in nodes) {
    final operation = operations[node.operation];
    if (operation == null) {
      issues.add(
        _issue(
          ModeRecipeViolation.unknownOperation,
          'nodes[${node.index}].operation',
        ),
      );
    } else {
      if (node.role != operation.role) {
        issues.add(
          _issue(ModeRecipeViolation.roleMismatch, 'nodes[${node.index}].role'),
        );
      }
      _checkPorts(node.inputs, operation.inputs, node.index, 'inputs', issues);
      _checkPorts(
        node.outputs,
        operation.outputs,
        node.index,
        'outputs',
        issues,
      );
      if (!_sameSet(
        node.requiredCapabilities,
        operation.requiredCapabilities,
      )) {
        issues.add(
          _issue(
            ModeRecipeViolation.nodeCapabilityMismatch,
            'nodes[${node.index}].required_capabilities',
          ),
        );
      }
      requiredPermissions.addAll(operation.permissions);
      _checkParameters(
        node.parameters,
        operation.parametersSchema,
        node.index,
        issues,
      );
    }
    for (final capability in node.requiredCapabilities.toList()..sort()) {
      capabilities.add(capability);
      if (!declaredCapabilities.contains(capability)) {
        issues.add(
          _issue(
            ModeRecipeViolation.undeclaredCapability,
            'nodes[${node.index}].required_capabilities[$capability]',
          ),
        );
      }
    }
  }

  // Exact permission scope: recipe permissions must equal the union of
  // permissions from operations actually used by unique nodes.
  for (final permission in requiredPermissions) {
    if (!shape.permissions.contains(permission)) {
      issues.add(_issue(ModeRecipeViolation.missingPermission, 'permissions'));
      break;
    }
  }
  for (final permission in shape.permissions) {
    if (!requiredPermissions.contains(permission)) {
      issues.add(_issue(ModeRecipeViolation.extraPermission, 'permissions'));
      break;
    }
  }

  final outputs = <String, List<String>>{};
  final inputs = <String, List<String>>{};
  final filledInputs = <({String node, String port})>{};
  final indegree = <String, int>{for (final node in nodes) node.id: 0};
  for (final edge in shape.edges) {
    final from = byId[edge.fromNode];
    final to = byId[edge.toNode];
    if (from == null) {
      issues.add(
        _issue(
          ModeRecipeViolation.edgeUnknownNode,
          'edges[${edge.index}].from_node',
        ),
      );
    }
    if (to == null) {
      issues.add(
        _issue(
          ModeRecipeViolation.edgeUnknownNode,
          'edges[${edge.index}].to_node',
        ),
      );
    }
    if (from != null && !from.outputs.containsKey(edge.fromPort)) {
      issues.add(
        _issue(
          ModeRecipeViolation.edgeUnknownPort,
          'edges[${edge.index}].from_port',
        ),
      );
    }
    if (to != null && !to.inputs.containsKey(edge.toPort)) {
      issues.add(
        _issue(
          ModeRecipeViolation.edgeUnknownPort,
          'edges[${edge.index}].to_port',
        ),
      );
    }
    if (from == null || to == null) continue;
    final outType = from.outputs[edge.fromPort];
    final inType = to.inputs[edge.toPort];
    if (outType != null && inType != null && outType != inType) {
      issues.add(
        _issue(ModeRecipeViolation.edgeTypeMismatch, 'edges[${edge.index}]'),
      );
    }
    if (!filledInputs.add((node: edge.toNode, port: edge.toPort))) {
      issues.add(
        _issue(
          ModeRecipeViolation.duplicateInputEdge,
          'edges[${edge.index}].to_port',
        ),
      );
    }
    outputs.putIfAbsent(edge.fromNode, () => <String>[]).add(edge.toNode);
    inputs.putIfAbsent(edge.toNode, () => <String>[]).add(edge.fromNode);
    indegree[edge.toNode] = indegree[edge.toNode]! + 1;
  }

  final ready = <String>[
    for (final node in nodes)
      if (indegree[node.id] == 0) node.id,
  ];
  final order = <String>[];
  for (var head = 0; head < ready.length; head++) {
    final id = ready[head];
    order.add(id);
    for (final next in outputs[id] ?? const <String>[]) {
      final remaining = indegree[next]! - 1;
      indegree[next] = remaining;
      if (remaining == 0) ready.add(next);
    }
  }
  if (order.length != nodes.length) {
    issues.add(_issue(ModeRecipeViolation.cyclicGraph, 'edges'));
  }

  final sourceIds = <String>[
    for (final node in nodes)
      if (node.role == 'source') node.id,
  ];
  final sinks = nodes.where((node) => node.role == 'sink').toList();
  final forward = _reachable(sourceIds, outputs);
  final backward = _reachable(sinks.map((node) => node.id), inputs);
  for (final node in nodes) {
    if (!forward.contains(node.id) || !backward.contains(node.id)) {
      issues.add(
        _issue(ModeRecipeViolation.disconnectedNode, 'nodes[${node.index}]'),
      );
    }
  }
  if (sourceIds.isEmpty) {
    issues.add(_issue(ModeRecipeViolation.missingSource, 'nodes'));
  }
  if (sinks.isEmpty) {
    issues.add(_issue(ModeRecipeViolation.missingSink, 'nodes'));
  }
  for (final node in nodes) {
    for (final port in node.inputs.keys.toList()..sort()) {
      if (!filledInputs.contains((node: node.id, port: port))) {
        issues.add(
          _issue(
            node.role == 'sink'
                ? ModeRecipeViolation.unconnectedSinkInput
                : ModeRecipeViolation.unconnectedInput,
            'nodes[${node.index}].inputs[$port]',
          ),
        );
      }
    }
  }

  return _result(
    issues,
    capabilities,
    issues.isEmpty ? order : const <String>[],
  );
}

void _checkPorts(
  Map<String, String> nodePorts,
  Map<String, String> registeredPorts,
  int index,
  String name,
  List<ModeRecipeIssue> issues,
) {
  final path = 'nodes[$index].$name';
  if (!_sameSet(nodePorts.keys, registeredPorts.keys)) {
    issues.add(
      _issue(
        name == 'inputs'
            ? ModeRecipeViolation.inputPortMismatch
            : ModeRecipeViolation.outputPortMismatch,
        path,
      ),
    );
    return;
  }
  final kind = name == 'inputs'
      ? ModeRecipeViolation.inputTypeMismatch
      : ModeRecipeViolation.outputTypeMismatch;
  for (final port in nodePorts.keys.toList()..sort()) {
    if (nodePorts[port] != registeredPorts[port]) {
      issues.add(_issue(kind, '$path[$port]'));
    }
  }
}

/// Minimal fail-closed check of [params] against [schema].
///
/// Supported subset: `type` must be `'object'` when present, `properties`
/// maps names to `{type}` where `type` is one of string/integer/number/
/// boolean/object/array/null, `required` is a string list, `additionalProperties`
/// is a bool (absent means allowed), and `minProperties`/`maxProperties` are
/// non-negative ints. Any other keyword, malformed value or non-object `type`
/// yields [ModeRecipeViolation.unsupportedParameterSchema] and skips further
/// parameter checks for that node. Paths are schema locations
/// (`nodes[i].parameters`) and never echo caller values.
void _checkParameters(
  Map<String, dynamic> params,
  Map<String, dynamic> schema,
  int index,
  List<ModeRecipeIssue> issues,
) {
  final path = 'nodes[$index].parameters';
  const allowedTop = {
    'type',
    'properties',
    'required',
    'additionalProperties',
    'minProperties',
    'maxProperties',
  };
  for (final key in schema.keys) {
    if (!allowedTop.contains(key)) {
      issues.add(_issue(ModeRecipeViolation.unsupportedParameterSchema, path));
      return;
    }
  }
  if (schema.containsKey('type') && schema['type'] != 'object') {
    issues.add(_issue(ModeRecipeViolation.unsupportedParameterSchema, path));
    return;
  }
  const allowedTypes = {
    'string',
    'integer',
    'number',
    'boolean',
    'object',
    'array',
    'null',
  };
  final properties = <String, Map>{};
  if (schema.containsKey('properties')) {
    final raw = schema['properties'];
    if (raw is! Map) {
      issues.add(_issue(ModeRecipeViolation.unsupportedParameterSchema, path));
      return;
    }
    for (final entry in raw.entries) {
      if (entry.key is! String || entry.value is! Map) {
        issues.add(
          _issue(ModeRecipeViolation.unsupportedParameterSchema, path),
        );
        return;
      }
      final declared = entry.value as Map;
      for (final key in declared.keys) {
        if (key != 'type') {
          issues.add(
            _issue(ModeRecipeViolation.unsupportedParameterSchema, path),
          );
          return;
        }
      }
      if (declared.containsKey('type')) {
        final type = declared['type'];
        if (type is! String || !allowedTypes.contains(type)) {
          issues.add(
            _issue(ModeRecipeViolation.unsupportedParameterSchema, path),
          );
          return;
        }
      }
      properties[entry.key as String] = declared;
    }
  }
  final required = <String>[];
  if (schema.containsKey('required')) {
    final raw = schema['required'];
    if (raw is! List) {
      issues.add(_issue(ModeRecipeViolation.unsupportedParameterSchema, path));
      return;
    }
    for (final value in raw) {
      if (value is! String) {
        issues.add(
          _issue(ModeRecipeViolation.unsupportedParameterSchema, path),
        );
        return;
      }
      required.add(value);
    }
  }
  var additional = true;
  if (schema.containsKey('additionalProperties')) {
    final raw = schema['additionalProperties'];
    if (raw is! bool) {
      issues.add(_issue(ModeRecipeViolation.unsupportedParameterSchema, path));
      return;
    }
    additional = raw;
  }
  int? minProperties;
  if (schema.containsKey('minProperties')) {
    final raw = schema['minProperties'];
    if (raw is! int || raw < 0) {
      issues.add(_issue(ModeRecipeViolation.unsupportedParameterSchema, path));
      return;
    }
    minProperties = raw;
  }
  int? maxProperties;
  if (schema.containsKey('maxProperties')) {
    final raw = schema['maxProperties'];
    if (raw is! int || raw < 0) {
      issues.add(_issue(ModeRecipeViolation.unsupportedParameterSchema, path));
      return;
    }
    maxProperties = raw;
  }
  if (minProperties != null &&
      maxProperties != null &&
      minProperties > maxProperties) {
    issues.add(_issue(ModeRecipeViolation.unsupportedParameterSchema, path));
    return;
  }
  if (minProperties != null && params.length < minProperties) {
    issues.add(_issue(ModeRecipeViolation.missingParameter, path));
  }
  if (maxProperties != null && params.length > maxProperties) {
    issues.add(_issue(ModeRecipeViolation.unexpectedParameter, path));
  }
  for (final name in required) {
    if (!params.containsKey(name)) {
      issues.add(_issue(ModeRecipeViolation.missingParameter, path));
      break;
    }
  }
  for (final entry in params.entries) {
    final declared = properties[entry.key];
    if (declared == null) {
      if (!additional) {
        issues.add(_issue(ModeRecipeViolation.unexpectedParameter, path));
        break;
      }
    } else if (declared.containsKey('type')) {
      if (!_matchesType(entry.value, declared['type'] as String)) {
        issues.add(_issue(ModeRecipeViolation.parameterTypeMismatch, path));
        break;
      }
    }
  }
}

bool _matchesType(Object? value, String type) {
  switch (type) {
    case 'string':
      return value is String;
    case 'integer':
      // JSON Schema integers include integral doubles such as 1.0 and 1e20.
      // round() saturates at the platform int maximum, so roundToDouble()
      // keeps large integral doubles valid; isFinite excludes NaN and infinity.
      return value is int ||
          (value is double && value.isFinite && value == value.roundToDouble());
    case 'number':
      return value is num;
    case 'boolean':
      return value is bool;
    case 'object':
      return value is Map;
    case 'array':
      return value is List;
    case 'null':
      return value == null;
  }
  return false;
}

bool _sameSet(Iterable<String> left, Iterable<String> right) {
  final a = left.toSet();
  final b = right.toSet();
  return a.length == b.length && a.containsAll(b);
}

Set<String> _reachable(
  Iterable<String> starts,
  Map<String, List<String>> edges,
) {
  final seen = starts.toSet();
  final queue = seen.toList();
  for (var head = 0; head < queue.length; head++) {
    for (final next in edges[queue[head]] ?? const <String>[]) {
      if (seen.add(next)) queue.add(next);
    }
  }
  return seen;
}

ModeRecipeValidation _result(
  List<ModeRecipeIssue> issues,
  Set<String> capabilities,
  List<String> order,
) {
  final sorted = issues.toSet().toList()
    ..sort((a, b) {
      final byKind = a.kind.index.compareTo(b.kind.index);
      return byKind != 0 ? byKind : a.path.compareTo(b.path);
    });
  final required = capabilities.toList()..sort();
  return ModeRecipeValidation._(
    List.unmodifiable(sorted),
    Set.unmodifiable(required),
    List.unmodifiable(order),
  );
}

ModeRecipeIssue _issue(ModeRecipeViolation kind, String path) =>
    ModeRecipeIssue(kind, path);

typedef _Issues = List<ModeRecipeIssue>;

class _Node {
  const _Node(
    this.index,
    this.id,
    this.operation,
    this.role,
    this.inputs,
    this.outputs,
    this.requiredCapabilities,
    this.parameters,
  );

  final int index;
  final String id;
  final String operation;
  final String role;
  final Map<String, String> inputs;
  final Map<String, String> outputs;
  final Set<String> requiredCapabilities;
  final Map<String, dynamic> parameters;
}

class _Edge {
  const _Edge(
    this.index,
    this.fromNode,
    this.fromPort,
    this.toNode,
    this.toPort,
  );

  final int index;
  final String fromNode;
  final String fromPort;
  final String toNode;
  final String toPort;
}

class _Operation {
  const _Operation(
    this.role,
    this.inputs,
    this.outputs,
    this.requiredCapabilities,
    this.permissions,
    this.parametersSchema,
  );

  final String role;
  final Map<String, String> inputs;
  final Map<String, String> outputs;
  final Set<String> requiredCapabilities;
  final Set<String> permissions;
  final Map<String, dynamic> parametersSchema;
}

typedef _RecipeShape = ({
  List<_Node> nodes,
  List<_Edge> edges,
  Set<String> permissions,
});

_RecipeShape? _readRecipe(Object? value, _Issues issues) {
  final root = _asMap(value, 'recipe', issues);
  if (root == null) return null;
  _fields(root, 'recipe', const {
    'id',
    'title_key',
    'nodes',
    'edges',
    'view',
    'target_policy',
    'permissions',
    'resource_profile',
    'processing_location',
    'retention',
  }, issues);
  for (final key in const ['id', 'title_key', 'view', 'resource_profile']) {
    _token(root, key, 'recipe', issues);
  }
  _enum(
    root,
    'target_policy',
    const {'selected_languages', 'viewer_preferences'},
    'recipe',
    issues,
  );
  _enum(root, 'retention', const {'session', 'project'}, 'recipe', issues);
  if (root['processing_location'] != 'device') {
    _bad(issues, 'recipe.processing_location');
  }
  final permissions = _tokenSet(root, 'permissions', 'recipe', issues);

  final nodes = <_Node>[];
  final rawNodes = _asList(root['nodes'], 'nodes', issues);
  if (rawNodes != null) {
    if (rawNodes.length < 2) _bad(issues, 'nodes');
    for (var i = 0; i < rawNodes.length; i++) {
      final path = 'nodes[$i]';
      final map = _asMap(rawNodes[i], path, issues);
      if (map == null) continue;
      _fields(map, path, const {
        'id',
        'operation',
        'role',
        'inputs',
        'outputs',
        'required_capabilities',
        'parameters',
      }, issues);
      final parameters = _asMap(map['parameters'], '$path.parameters', issues);
      final id = _token(map, 'id', path, issues);
      final operation = _token(map, 'operation', path, issues);
      final role = _enum(
        map,
        'role',
        const {'source', 'processor', 'sink'},
        path,
        issues,
      );
      final inputs = _ports(map['inputs'], '$path.inputs', issues);
      final outputs = _ports(map['outputs'], '$path.outputs', issues);
      final capabilities = _tokenSet(
        map,
        'required_capabilities',
        path,
        issues,
      );
      if (id != null &&
          operation != null &&
          role != null &&
          inputs != null &&
          outputs != null &&
          capabilities != null &&
          parameters != null) {
        nodes.add(
          _Node(
            i,
            id,
            operation,
            role,
            inputs,
            outputs,
            capabilities,
            parameters,
          ),
        );
      }
    }
  }

  final edges = <_Edge>[];
  final rawEdges = _asList(root['edges'], 'edges', issues);
  if (rawEdges != null) {
    if (rawEdges.isEmpty) _bad(issues, 'edges');
    final seen =
        <({String fromNode, String fromPort, String toNode, String toPort})>{};
    for (var i = 0; i < rawEdges.length; i++) {
      final path = 'edges[$i]';
      final map = _asMap(rawEdges[i], path, issues);
      if (map == null) continue;
      _fields(map, path, const {
        'from_node',
        'from_port',
        'to_node',
        'to_port',
      }, issues);
      final fromNode = _token(map, 'from_node', path, issues);
      final fromPort = _token(map, 'from_port', path, issues);
      final toNode = _token(map, 'to_node', path, issues);
      final toPort = _token(map, 'to_port', path, issues);
      if (fromNode != null &&
          fromPort != null &&
          toNode != null &&
          toPort != null) {
        if (!seen.add((
          fromNode: fromNode,
          fromPort: fromPort,
          toNode: toNode,
          toPort: toPort,
        ))) {
          _bad(issues, path);
        }
        edges.add(_Edge(i, fromNode, fromPort, toNode, toPort));
      }
    }
  }
  return (
    nodes: nodes,
    edges: edges,
    permissions: permissions ?? const <String>{},
  );
}

Map<String, _Operation>? _readRegistry(Object? value, _Issues issues) {
  final map = _asMap(value, 'registry', issues);
  if (map == null) return null;
  final operations = <String, _Operation>{};
  var index = 0;
  for (final entry in map.entries) {
    final path = 'registry[$index]';
    index++;
    if (!_isToken(entry.key)) {
      _bad(issues, path);
      continue;
    }
    final operation = entry.key;
    final declaration = _asMap(entry.value, path, issues);
    if (declaration == null) continue;
    _fields(declaration, path, const {
      'role',
      'inputs',
      'outputs',
      'required_capabilities',
      'permissions',
      'parameters_schema',
    }, issues);
    final parametersSchema = _asMap(
      declaration['parameters_schema'],
      '$path.parameters_schema',
      issues,
    );
    final role = _enum(
      declaration,
      'role',
      const {'source', 'processor', 'sink'},
      path,
      issues,
    );
    final inputs = _ports(declaration['inputs'], '$path.inputs', issues);
    final outputs = _ports(declaration['outputs'], '$path.outputs', issues);
    // The registry is a developer-provided contract map, not a JSON-schema
    // document: validate_recipe compares these fields as sets, so repeated
    // tokens carry no meaning and must not reject an otherwise valid recipe.
    final capabilities = _tokenSet(
      declaration,
      'required_capabilities',
      path,
      issues,
      unique: false,
    );
    final permissions = _tokenSet(
      declaration,
      'permissions',
      path,
      issues,
      unique: false,
    );
    if (role != null &&
        inputs != null &&
        outputs != null &&
        capabilities != null &&
        permissions != null &&
        parametersSchema != null) {
      operations[operation] = _Operation(
        role,
        inputs,
        outputs,
        capabilities,
        permissions,
        parametersSchema,
      );
    }
  }
  return operations;
}

void _bad(_Issues issues, String path) =>
    issues.add(_issue(ModeRecipeViolation.invalidShape, path));

Map<String, dynamic>? _asMap(Object? value, String path, _Issues issues) {
  if (value is! Map) {
    _bad(issues, path);
    return null;
  }
  final map = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      _bad(issues, path);
      continue;
    }
    map[entry.key as String] = entry.value;
  }
  return map;
}

Map<String, String>? _ports(Object? value, String path, _Issues issues) {
  final map = _asMap(value, path, issues);
  if (map == null) return null;
  final ports = <String, String>{};
  var index = 0;
  for (final entry in map.entries) {
    final portPath = '$path[$index]';
    index++;
    if (!_isToken(entry.key) || !_isToken(entry.value)) {
      _bad(issues, portPath);
      continue;
    }
    ports[entry.key] = entry.value as String;
  }
  return ports;
}

List<dynamic>? _asList(Object? value, String path, _Issues issues) {
  if (value is! List) {
    _bad(issues, path);
    return null;
  }
  return value;
}

void _fields(
  Map<String, dynamic> map,
  String path,
  Set<String> fields,
  _Issues issues,
) {
  for (final key in fields) {
    if (!map.containsKey(key)) _bad(issues, '$path.$key');
  }
  for (final key in map.keys) {
    if (!fields.contains(key)) _bad(issues, '$path.$key');
  }
}

final RegExp _tokenPattern = RegExp(r'^[a-z][a-z0-9._-]*$');

bool _isToken(Object? value) =>
    value is String && _tokenPattern.hasMatch(value);

String? _token(
  Map<String, dynamic> map,
  String key,
  String path,
  _Issues issues,
) {
  final value = map[key];
  if (!_isToken(value)) {
    _bad(issues, '$path.$key');
    return null;
  }
  return value as String;
}

String? _enum(
  Map<String, dynamic> map,
  String key,
  Set<String> allowed,
  String path,
  _Issues issues,
) {
  final value = map[key];
  if (value is! String || !allowed.contains(value)) {
    _bad(issues, '$path.$key');
    return null;
  }
  return value;
}

Set<String>? _tokenSet(
  Map<String, dynamic> map,
  String key,
  String path,
  _Issues issues, {
  bool unique = true,
}) {
  final value = map[key];
  if (value is! List) {
    _bad(issues, '$path.$key');
    return null;
  }
  final result = <String>{};
  for (var i = 0; i < value.length; i++) {
    final item = value[i];
    if (!_isToken(item)) {
      _bad(issues, '$path.$key[$i]');
    } else if (unique && !result.add(item as String)) {
      _bad(issues, '$path.$key[$i]');
    } else {
      result.add(item as String);
    }
  }
  return result;
}
