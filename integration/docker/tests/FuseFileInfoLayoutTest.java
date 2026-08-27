/*
 * The Alluxio Open Foundation licenses this work under the Apache License, version 2.0
 * (the "License"). You may not use this work except in compliance with the License, which is
 * available at www.apache.org/licenses/LICENSE-2.0
 *
 * This software is distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
 * either express or implied, as more fully set forth in the License.
 *
 * See the NOTICE file distributed with this work for information regarding copyright ownership.
 */

package alluxio.jnifuse.struct;

import jnr.ffi.Pointer;
import jnr.ffi.Runtime;
import jnr.ffi.Struct;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/** Verifies the Java view of the Linux libfuse file handle structures. */
public final class FuseFileInfoLayoutTest {
  private static final int STRUCT_SIZE = 40;
  private static final int FLAGS = 0x20000;
  private static final long FILE_HANDLE = 0x1020304050607080L;

  private FuseFileInfoLayoutTest() {}

  private static ByteBuffer newBuffer() {
    return ByteBuffer.allocateDirect(STRUCT_SIZE).order(ByteOrder.LITTLE_ENDIAN);
  }

  private static void bind(FuseFileInfo fileInfo, ByteBuffer buffer) {
    fileInfo.useMemory(Pointer.wrap(fileInfo.getRuntime(), buffer));
  }

  private static void checkFuse3(Runtime runtime) {
    ByteBuffer buffer = newBuffer();
    buffer.putInt(0, FLAGS);
    FuseFileInfo fileInfo = new Fuse3FuseFileInfo(runtime, buffer);
    bind(fileInfo, buffer);

    check(fileInfo.flags.get() == FLAGS, "FUSE3 flags must be read at offset 0");
    fileInfo.fh.set(FILE_HANDLE);
    check(fileInfo.fh.get() == FILE_HANDLE, "FUSE3 fh must round-trip");
    check(buffer.getLong(16) == FILE_HANDLE, "FUSE3 fh must be written at offset 16");
    check(Struct.size(fileInfo) == STRUCT_SIZE, "FUSE3 Java struct size must be 40");
  }

  private static void checkFuse2(Runtime runtime) {
    ByteBuffer buffer = newBuffer();
    buffer.putInt(0, FLAGS);
    FuseFileInfo fileInfo = new Fuse2FuseFileInfo(runtime, buffer);
    bind(fileInfo, buffer);

    check(fileInfo.flags.get() == FLAGS, "FUSE2 flags must be read at offset 0");
    fileInfo.fh.set(FILE_HANDLE);
    check(fileInfo.fh.get() == FILE_HANDLE, "FUSE2 fh must round-trip");
    check(buffer.getLong(24) == FILE_HANDLE, "FUSE2 fh must be written at offset 24");
    check(Struct.size(fileInfo) == STRUCT_SIZE, "FUSE2 Java struct size must be 40");
  }

  private static void check(boolean condition, String message) {
    if (!condition) {
      throw new AssertionError(message);
    }
  }

  public static void main(String[] args) {
    Runtime runtime = Runtime.getSystemRuntime();
    checkFuse3(runtime);
    checkFuse2(runtime);
    System.out.println("PASS: FuseFileInfo matches Linux FUSE2 and FUSE3 layouts");
  }
}
