class_name NsbmdRig
extends Node3D
## A skinned model: one mesh whose vertices follow the bones of the model's skeleton, so
## that an animation can pose it. `apply_pose()` moves the bones.

var source: Nsbmd
var model_index := 0
var bind_bounds := AABB()      # box of the model in its bind pose
var world := {}                # node id -> Transform3D, after the last apply_pose()

var _skeleton: Skeleton3D
var _instance: MeshInstance3D


## Called once by Nsbmd.build_rig().
func setup(mesh: ArrayMesh, node_count: int) -> void:
	_skeleton = Skeleton3D.new()
	_skeleton.name = "Skeleton"
	add_child(_skeleton)
	for i in node_count:
		_skeleton.add_bone("node_%d" % i)
	var skin := Skin.new()
	for i in node_count:
		skin.add_bind(i, Transform3D.IDENTITY)   # vertices are in their node's own space
	_instance = MeshInstance3D.new()
	_instance.mesh = mesh
	_instance.skin = skin
	_skeleton.add_child(_instance)
	_instance.skeleton = NodePath("..")


## `pose` is a list of local node transforms (see NitroAnim.pose); empty = bind pose.
func apply_pose(pose: Array = []) -> void:
	world = source.skeleton(model_index, pose)
	for id: int in world:
		_skeleton.set_bone_global_pose_override(id, world[id], 1.0, true)


## World transform of a node by name (identity if unknown).
func node_transform(node_name: String) -> Transform3D:
	var nodes: Array = source.models[model_index].nodes
	for i in nodes.size():
		if nodes[i].name == node_name:
			return world.get(i, Transform3D.IDENTITY)
	return Transform3D.IDENTITY


## Box of the model in the bind pose, for centring and scaling.
func bounds() -> AABB:
	return bind_bounds
