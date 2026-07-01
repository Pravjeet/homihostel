import 'package:cloud_firestore/cloud_firestore.dart';

// =====================================================
// 1. PERMISSIONS DATA MODEL
// =====================================================
class RolePermissions {
  final String roleName;
  final bool canRead;
  final bool canGet;
  final bool canList;
  final bool canWrite;
  final bool canCreate;
  final bool canUpdate;
  final bool canDelete;

  RolePermissions({
    required this.roleName,
    this.canRead = false,
    this.canGet = false,
    this.canList = false,
    this.canWrite = false,
    this.canCreate = false,
    this.canUpdate = false,
    this.canDelete = false,
  });

  factory RolePermissions.fromMap(Map<String, dynamic> map, String role) {
    return RolePermissions(
      roleName: role,
      canRead: map['read'] ?? false,
      canGet: map['get'] ?? false,
      canList: map['list'] ?? false,
      canWrite: map['write'] ?? false,
      canCreate: map['create'] ?? false,
      canUpdate: map['update'] ?? false,
      canDelete: map['delete'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'read': canRead,
      'get': canGet,
      'list': canList,
      'write': canWrite,
      'create': canCreate,
      'update': canUpdate,
      'delete': canDelete,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  RolePermissions copyWith({
    bool? canRead,
    bool? canGet,
    bool? canList,
    bool? canWrite,
    bool? canCreate,
    bool? canUpdate,
    bool? canDelete,
  }) {
    return RolePermissions(
      roleName: roleName,
      canRead: canRead ?? this.canRead,
      canGet: canGet ?? this.canGet,
      canList: canList ?? this.canList,
      canWrite: canWrite ?? this.canWrite,
      canCreate: canCreate ?? this.canCreate,
      canUpdate: canUpdate ?? this.canUpdate,
      canDelete: canDelete ?? this.canDelete,
    );
  }

  // Helper to get all permissions as a map
  Map<String, bool> toPermissionMap() {
    return {
      'read': canRead,
      'get': canGet,
      'list': canList,
      'write': canWrite,
      'create': canCreate,
      'update': canUpdate,
      'delete': canDelete,
    };
  }

  // Create from permission map
  static RolePermissions fromPermissionMap(
    String roleName,
    Map<String, bool> permissions,
  ) {
    return RolePermissions(
      roleName: roleName,
      canRead: permissions['read'] ?? false,
      canGet: permissions['get'] ?? false,
      canList: permissions['list'] ?? false,
      canWrite: permissions['write'] ?? false,
      canCreate: permissions['create'] ?? false,
      canUpdate: permissions['update'] ?? false,
      canDelete: permissions['delete'] ?? false,
    );
  }
}

// =====================================================
// 2. PERMISSIONS SERVICE
// =====================================================
class PermissionsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Initialize default permissions for a new college (Only SuperAdmin)
  Future<void> initializeDefaultPermissions(String collegeId) async {
    WriteBatch batch = _firestore.batch();

    // Create ONLY SuperAdmin role with full permissions
    DocumentReference superAdminRef = _firestore
        .collection('colleges')
        .doc(collegeId)
        .collection('role_permissions')
        .doc('SuperAdmin');

    batch.set(superAdminRef, {
      'read': true,
      'get': true,
      'list': true,
      'write': true,
      'create': true,
      'update': true,
      'delete': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Get permissions for a specific role
  Future<RolePermissions?> getPermissionsForRole(
    String collegeId,
    String roleName,
  ) async {
    try {
      DocumentSnapshot<Map<String, dynamic>> doc = await _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('role_permissions')
          .doc(roleName)
          .get();

      if (doc.exists && doc.data() != null) {
        return RolePermissions.fromMap(doc.data()!, roleName);
      }
      return null;
    } catch (e) {
      print("🚨 Error fetching permissions: $e");
      return null;
    }
  }

  /// Get all role permissions
  Future<List<RolePermissions>> getAllRolePermissions(String collegeId) async {
    try {
      QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('role_permissions')
          .get();

      return snapshot.docs
          .map((doc) => RolePermissions.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print("🚨 Error fetching all permissions: $e");
      return [];
    }
  }

  /// Get all available roles (excluding SuperAdmin)
  Future<List<String>> getAvailableRoles(String collegeId) async {
    try {
      QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('role_permissions')
          .get();

      List<String> roles = [];
      for (var doc in snapshot.docs) {
        if (doc.id != 'SuperAdmin') {
          roles.add(doc.id);
        }
      }
      return roles;
    } catch (e) {
      print("🚨 Error fetching roles: $e");
      return [];
    }
  }

  /// Update a specific role's permissions
  Future<void> updateRolePermission({
    required String collegeId,
    required RolePermissions updatedPermission,
  }) async {
    try {
      await _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('role_permissions')
          .doc(updatedPermission.roleName)
          .update(updatedPermission.toMap());
    } catch (e) {
      print("🚨 Error updating permissions: $e");
      throw Exception("Failed to update permissions.");
    }
  }

  /// Create a new role with permissions
  Future<void> createRoleWithPermissions({
    required String collegeId,
    required String roleName,
    required Map<String, bool> permissions,
  }) async {
    try {
      final rolePermissions = RolePermissions.fromPermissionMap(
        roleName,
        permissions,
      );
      await _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('role_permissions')
          .doc(roleName)
          .set(rolePermissions.toMap());
    } catch (e) {
      print("🚨 Error creating role: $e");
      throw Exception("Failed to create role.");
    }
  }

  /// Delete a role and its permissions (Cannot delete SuperAdmin)
  Future<void> deleteRolePermissions({
    required String collegeId,
    required String roleName,
  }) async {
    try {
      if (roleName == 'SuperAdmin') {
        throw Exception("Cannot delete SuperAdmin role.");
      }

      // Delete the role permissions document
      await _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('role_permissions')
          .doc(roleName)
          .delete();

      // Reset all users with this role to unassigned
      final usersSnapshot = await _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('users')
          .where('role', isEqualTo: roleName)
          .get();

      WriteBatch batch = _firestore.batch();
      for (var doc in usersSnapshot.docs) {
        batch.update(doc.reference, {'role': null});
      }
      await batch.commit();
    } catch (e) {
      print("🚨 Error deleting role: $e");
      throw Exception("Failed to delete role.");
    }
  }

  /// Clean up all roles (delete all except SuperAdmin and reset users)
  Future<void> cleanupAllRoles(String collegeId) async {
    try {
      WriteBatch batch = _firestore.batch();

      // Get all role permissions
      final rolesSnapshot = await _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('role_permissions')
          .get();

      // Delete all roles except SuperAdmin
      for (var doc in rolesSnapshot.docs) {
        if (doc.id != 'SuperAdmin') {
          batch.delete(doc.reference);
        }
      }

      // Reset all users who have non-SuperAdmin roles to null
      final usersSnapshot = await _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('users')
          .get();

      for (var doc in usersSnapshot.docs) {
        final userRole = doc.data()['role'];
        if (userRole != null && userRole != 'SuperAdmin') {
          batch.update(doc.reference, {'role': null});
        }
      }

      await batch.commit();
    } catch (e) {
      print("🚨 Error cleaning up roles: $e");
      throw Exception("Failed to clean up roles.");
    }
  }

  /// Check if a user has a specific permission
  Future<bool> hasPermission({
    required String collegeId,
    required String roleName,
    required String permissionKey, // 'read', 'write', 'create', etc.
  }) async {
    try {
      final rolePermissions = await getPermissionsForRole(collegeId, roleName);
      if (rolePermissions == null) return false;

      switch (permissionKey) {
        case 'read':
          return rolePermissions.canRead;
        case 'get':
          return rolePermissions.canGet;
        case 'list':
          return rolePermissions.canList;
        case 'write':
          return rolePermissions.canWrite;
        case 'create':
          return rolePermissions.canCreate;
        case 'update':
          return rolePermissions.canUpdate;
        case 'delete':
          return rolePermissions.canDelete;
        default:
          return false;
      }
    } catch (e) {
      print("🚨 Error checking permission: $e");
      return false;
    }
  }

  /// Get all available permission keys with labels
  static List<Map<String, String>> getAvailablePermissions() {
    return [
      {'key': 'read', 'label': 'Read Data', 'description': 'View all data'},
      {'key': 'get', 'label': 'Get Data', 'description': 'View specific data'},
      {
        'key': 'list',
        'label': 'List Data',
        'description': 'View lists of data',
      },
      {
        'key': 'write',
        'label': 'Write Data',
        'description': 'Create, update, delete all data',
      },
      {
        'key': 'create',
        'label': 'Create Data',
        'description': 'Create new data',
      },
      {
        'key': 'update',
        'label': 'Update Data',
        'description': 'Update existing data',
      },
      {
        'key': 'delete',
        'label': 'Delete Data',
        'description': 'Delete existing data',
      },
    ];
  }

  /// Get permission categories for UI grouping
  static Map<String, List<Map<String, String>>> getPermissionCategories() {
    return {
      'Read Operations': [
        {'key': 'read', 'label': 'Read All', 'description': 'View all data'},
        {'key': 'get', 'label': 'Get', 'description': 'View specific data'},
        {'key': 'list', 'label': 'List', 'description': 'View lists of data'},
      ],
      'Write Operations': [
        {
          'key': 'write',
          'label': 'Write All',
          'description': 'Create, update, delete all',
        },
        {'key': 'create', 'label': 'Create', 'description': 'Create new data'},
        {
          'key': 'update',
          'label': 'Update',
          'description': 'Update existing data',
        },
        {
          'key': 'delete',
          'label': 'Delete',
          'description': 'Delete existing data',
        },
      ],
    };
  }
}
