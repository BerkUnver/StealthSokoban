import bmesh
import bpy
import bpy_extras
import struct


class ToExport():
    def __init__(self, obj, mesh, mesh_to_world):
        self.obj = obj
        self.mesh = mesh
        self.mesh_to_world = mesh_to_world


def export_my_mesh(context, operator):
    bm = bmesh.new()
    dependency_graph = context.evaluated_depsgraph_get()
    
    for obj in context.scene.collection.all_objects:
        if obj.type == "MESH":
            n = len(bm.verts)
            bm.from_object(obj, dependency_graph)
            bmesh.ops.transform(bm, verts=bm.verts[n:], matrix=obj.matrix_world)

    bmesh.ops.triangulate(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("Export Mesh")
    bm.to_mesh(mesh)

        
    if not mesh.uv_layers or len(mesh.uv_layers) == 0:
        operator.report({"ERROR"}, "There's a mesh without uv layers in this scene. We don't support that.")
        return {"CANCELLED"}
        meshes

    if len(mesh.uv_layers) > 1:
        operator.report({"ERROR"}, "There's a mesh with more than 1 uv layer in the scene. We don't support that.")
        return {"CANCELLED"}

    uvs = mesh.uv_layers[0].uv

    data = bytearray()

    index_count = len(mesh.loop_triangles)
    vertex_count = len(mesh.loops)
    s = struct.pack("<II", index_count, vertex_count)
    data.extend(s)

    for i in range(vertex_count):
        loop = mesh.loops[i]
        position = mesh.vertices[loop.vertex_index].co
        uv = uvs[i].vector

        s = struct.pack("<5f", position.x, position.z, position.y, uv.x, uv.y)
        data.extend(s)
    
    f = open(operator.filepath, "wb")
    f.write(data)
    f.close()

    return {"FINISHED"}

"""
def export_my_mesh(context, operator):
    to_export_array = []
    
    for obj in context.scene.collection.all_objects:
        if obj.type == "MESH":
            bm = bmesh.new()
            bm.from_object(obj)
            bmesh.ops.transform(bm, verts = bm.verts, matrix=obj.matrix_world)
            mesh = bpy.data.meshes.new()
            bm.to_mesh(mesh)
            to_export_array.append(ToExport(obj, mesh, obj.matrix_world))
            # TODO: Filter out hidden meshes

    data = bytearray()
    vertex_count = 0
    index_count = 0
    
    print(f"Mesh count: {len(to_export_array)}")
    
    for to_export in to_export_array:
        vertex_count += len(to_export.mesh.loops)
        index_count += len(to_export.mesh.loop_triangles)
    index_count *= 3 # 3 verts per triangle
    
    print(f"Index count: {index_count}")
    print(f"Vertex count: {vertex_count}")
    
    s = struct.pack("<II", index_count, vertex_count)
    data.extend(s)
    
    for to_export in to_export_array:
        for tri in to_export.mesh.loop_triangles:
            s = struct.pack("<3I", *tri.loops)
            data.extend(s)
        
    for to_export in to_export_array:
        vertex_count = len(to_export.mesh.loops)
        if not to_export.mesh.uv_layers:
            operator.report({"ERROR"}, "There's a mesh without uv layers in this scene. We don't support that.")
            return {"CANCELLED"}
            meshes

        if len(to_export.mesh.uv_layers) > 1:
            operator.report({"ERROR"}, "There's a mesh with more than 1 uv layer in the scene. We don't support that.")
            return {"CANCELLED"}

        uvs = to_export.mesh.uv_layers[0].uv
        for i in range(vertex_count):
            loop = to_export.mesh.loops[i]
            uv = uvs[i].vector
            
            vertex = to_export.mesh.vertices[loop.vertex_index]
            position = to_export.mesh_to_world @ vertex.co
            
            s = struct.pack("<5f", position.x, position.z, position.y, uv.x, uv.y)
            data.extend(s)
    
    f = open(operator.filepath, "wb")
    f.write(data)
    f.close()

    return {"FINISHED"}
"""

class MyMeshExporter(bpy.types.Operator, bpy_extras.io_utils.ExportHelper):
    bl_idname = "export.my_mesh_exporter"
    bl_label = "Export My Mesh"

    filename_ext = ".my_mesh"

    filter_glob: bpy.props.StringProperty(
        default="*.my_mesh",
        options={"HIDDEN"},
        maxlen=255,
    )

    def execute(self, context):
        return export_my_mesh(context, self)


def menu_func_export(self, context):
    self.layout.operator(MyMeshExporter.bl_idname, text="My Mesh (.my_mesh)")


def register():
    bpy.utils.register_class(MyMeshExporter)
    bpy.types.TOPBAR_MT_file_export.append(menu_func_export)


def unregister():
    bpy.utils.unregister_class(MyMeshExporter)
    bpy.types.TOPBAR_MT_file_export.remove(menu_func_export)


if __name__ == "__main__":
    register()
