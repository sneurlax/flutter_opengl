enum PointerEventType {
  onPointerDown,
  onPointerMove,
  onPointerUp,
}

enum UniformType {
  uniformBool,
  uniformInt,
  uniformFloat,
  uniformVec2,
  uniformVec3,
  uniformVec4,
  uniformMat2,
  uniformMat3,
  uniformMat4,
  uniformSampler2D,
}

enum AddMethod {
  /// Add Sampler2D uniform if not already exists
  add,

  /// Replace Sampler2D uniform with another with different size
  replace,

  /// Set a new Sampler2D uniform with the same size
  set,
}
