import bmesh
import bpy
import bpy_extras
import struct


def export_my_mesh(context, operator):
    bm = bmesh.new()
    dependency_graph = context.evaluated_depsgraph_get()
    
    for obj in context.scene.collection.all_objects:
        if obj.type == "MESH":
            n = len(bm.verts)
            bm.from_object(obj, dependency_graph)
            bmesh.ops.transform(bm, verts=bm.verts[n:], matrix=obj.matrix_world)

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

    # @TODO: The way we are exporting vertices is not very efficient.
    # It exports each vertex of each face as a unique vertex. In
    # Blender, faces can be non-triangular. This allows us to have,
    # for example, 4 verts per face instead of 6. However, this is
    # still not very good. The actual way to do this is to figure out
    # what vertices are identical and collapse those into one vertex.
    # I don't know if there is a way to do this with the Blender API
    # or if we have to do it ourselves.
    #           -berk, 2025 - 3 - 24
    
    index_count = len(mesh.loop_triangles) * 3
    vertex_count = len(mesh.loops)
    s = struct.pack("<II", index_count, vertex_count)
    data.extend(s)
    
    # Pack indices
    for triangle in mesh.loop_triangles:
        s = struct.pack("<3I", *triangle.loops)
        data.extend(s)
            
    
    # Pack vertices
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
