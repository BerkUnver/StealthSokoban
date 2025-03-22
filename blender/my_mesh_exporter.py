import bpy
import bpy_extras
import struct

def export_my_mesh(context, filepath):
    f = open(filepath, "wb")
    
    vertex_count = 0
    for mesh in bpy.data.meshes:
        vertex_count += len(mesh.vertices)
    s = struct.pack("<Q", vertex_count)
    f.write(s)
    
    for mesh in bpy.data.meshes:
        for vertex in mesh.vertices:
            s = struct.pack("<fff", vertex.co.x, vertex.co.z, vertex.co.y)
            f.write(s)
    
    # Because python, it keeps inserting a newline when I close the file.
    # I will just ignore it for now, I do not want to spend time to figure it out.
    f.close()

    return {'FINISHED'}


class MyMeshExporter(bpy.types.Operator, bpy_extras.io_utils.ExportHelper):
    bl_idname = "export.my_mesh_exporter"
    bl_label = "Export Triangle Mesh"

    filename_ext = ".my_mesh"

    filter_glob: bpy.props.StringProperty(
        default="*.my_mesh",
        options={"HIDDEN"},
        maxlen=255,
    )

    def execute(self, context):
        return export_my_mesh(context, self.filepath)


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
