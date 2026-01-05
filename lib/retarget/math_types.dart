import 'dart:math' as math;

/// Lightweight math types used by the retarget system.
/// Pure Dart (no engine dependency) so code is easy to test and port.

class Vec3 {
  double x;
  double y;
  double z;

  Vec3([this.x = 0, this.y = 0, this.z = 0]);

  Vec3.clone(Vec3 other) : this(other.x, other.y, other.z);

  Vec3 copyFrom(Vec3 other) {
    x = other.x;
    y = other.y;
    z = other.z;
    return this;
  }

  Vec3 set(double nx, double ny, double nz) {
    x = nx;
    y = ny;
    z = nz;
    return this;
  }

  Vec3 add(Vec3 other) {
    x += other.x;
    y += other.y;
    z += other.z;
    return this;
  }

  Vec3 sub(Vec3 other) {
    x -= other.x;
    y -= other.y;
    z -= other.z;
    return this;
  }

  Vec3 scaled(double s) => Vec3(x * s, y * s, z * s);

  Vec3 scale(double s) {
    x *= s;
    y *= s;
    z *= s;
    return this;
  }

  double dot(Vec3 other) => x * other.x + y * other.y + z * other.z;

  Vec3 cross(Vec3 other) {
    final cx = y * other.z - z * other.y;
    final cy = z * other.x - x * other.z;
    final cz = x * other.y - y * other.x;
    x = cx;
    y = cy;
    z = cz;
    return this;
  }

  Vec3 setFromCross(Vec3 a, Vec3 b) {
    x = a.y * b.z - a.z * b.y;
    y = a.z * b.x - a.x * b.z;
    z = a.x * b.y - a.y * b.x;
    return this;
  }

  double get lengthSq => x * x + y * y + z * z;

  double get length => lengthSq == 0 ? 0 : math.sqrt(lengthSq);

  Vec3 normalize() {
    final lenSq = lengthSq;
    if (lenSq == 0) return this;
    final invLen = 1.0 / math.sqrt(lenSq);
    x *= invLen;
    y *= invLen;
    z *= invLen;
    return this;
  }

  double distanceTo(Vec3 other) {
    final dx = x - other.x;
    final dy = y - other.y;
    final dz = z - other.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }
}

class Quat {
  double x;
  double y;
  double z;
  double w;

  Quat([this.x = 0, this.y = 0, this.z = 0, this.w = 1]);

  Quat.clone(Quat other) : this(other.x, other.y, other.z, other.w);

  Quat copyFrom(Quat other) {
    x = other.x;
    y = other.y;
    z = other.z;
    w = other.w;
    return this;
  }

  Quat set(double nx, double ny, double nz, double nw) {
    x = nx;
    y = ny;
    z = nz;
    w = nw;
    return this;
  }

  /// Multiply this * other (in-place).
  Quat multiply(Quat other) {
    final qx = x;
    final qy = y;
    final qz = z;
    final qw = w;

    x = qw * other.x + qx * other.w + qy * other.z - qz * other.y;
    y = qw * other.y - qx * other.z + qy * other.w + qz * other.x;
    z = qw * other.z + qx * other.y - qy * other.x + qz * other.w;
    w = qw * other.w - qx * other.x - qy * other.y - qz * other.z;
    return this;
  }

  Quat normalized() {
    final lenSq = x * x + y * y + z * z + w * w;
    if (lenSq == 0) return this;
    final invLen = 1.0 / math.sqrt(lenSq);
    x *= invLen;
    y *= invLen;
    z *= invLen;
    w *= invLen;
    return this;
  }

  Quat invert() {
    x = -x;
    y = -y;
    z = -z;
    // w stays the same (unit quaternion)
    return this;
  }

  /// Set quaternion from Euler angles (XYZ order, intrinsic rotations).
  /// Angles are in radians.
  Quat setFromEuler(double ex, double ey, double ez) {
    final c1 = math.cos(ex / 2);
    final c2 = math.cos(ey / 2);
    final c3 = math.cos(ez / 2);
    final s1 = math.sin(ex / 2);
    final s2 = math.sin(ey / 2);
    final s3 = math.sin(ez / 2);

    // XYZ order
    x = s1 * c2 * c3 + c1 * s2 * s3;
    y = c1 * s2 * c3 - s1 * c2 * s3;
    z = c1 * c2 * s3 + s1 * s2 * c3;
    w = c1 * c2 * c3 - s1 * s2 * s3;

    return this;
  }

  /// Create quaternion from axis-angle rotation.
  Quat setFromAxisAngle(Vec3 axis, double angle) {
    final halfAngle = angle / 2;
    final s = math.sin(halfAngle);
    x = axis.x * s;
    y = axis.y * s;
    z = axis.z * s;
    w = math.cos(halfAngle);
    return this;
  }

  /// Slerp towards [target] by factor [t] (0..1).
  Quat slerp(Quat target, double t) {
    double cosHalfTheta =
        x * target.x + y * target.y + z * target.z + w * target.w;

    if (cosHalfTheta < 0) {
      cosHalfTheta = -cosHalfTheta;
      target = Quat(-target.x, -target.y, -target.z, -target.w);
    }

    if (cosHalfTheta >= 1.0) {
      return this;
    }

    final halfTheta =
        math.atan2(math.sqrt(1.0 - cosHalfTheta * cosHalfTheta), cosHalfTheta);
    if (halfTheta.abs() < 0.001) {
      x = 0.5 * (x + target.x);
      y = 0.5 * (y + target.y);
      z = 0.5 * (z + target.z);
      w = 0.5 * (w + target.w);
      return this;
    }

    final sinHalfTheta = math.sqrt(1.0 - cosHalfTheta * cosHalfTheta);
    final ratioA = math.sin((1 - t) * halfTheta) / sinHalfTheta;
    final ratioB = math.sin(t * halfTheta) / sinHalfTheta;

    x = x * ratioA + target.x * ratioB;
    y = y * ratioA + target.y * ratioB;
    z = z * ratioA + target.z * ratioB;
    w = w * ratioA + target.w * ratioB;
    return this;
  }
}
