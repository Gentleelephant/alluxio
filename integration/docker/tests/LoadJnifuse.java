import alluxio.jnifuse.LibFuse;
import alluxio.jnifuse.utils.LibfuseVersion;

/** Loads both JNI FUSE variants without mounting a filesystem. */
public final class LoadJnifuse {
  private LoadJnifuse() {}

  public static void main(String[] args) {
    LibfuseVersion version = args.length > 0 && "2".equals(args[0])
        ? LibfuseVersion.VERSION_2 : LibfuseVersion.VERSION_3;
    LibFuse.loadLibrary(version);
    System.out.println("Loaded JNI FUSE version " + version);
  }
}
