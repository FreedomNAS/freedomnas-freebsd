--- target/i386/nvmm/nvmm-all.c.orig
+++ target/i386/nvmm/nvmm-all.c
@@ -1060,8 +1060,9 @@
     ram_addr_t size = int128_get64(section->size);
     unsigned int delta;
     uintptr_t hva;
+    bool romd = memory_region_is_romd(mr);
 
-    if (!memory_region_is_ram(mr)) {
+    if (!memory_region_is_ram(mr) && !romd) {
         return;
     }
 
@@ -1082,7 +1083,7 @@
         section->offset_within_region + delta;
 
     nvmm_update_mapping(start_pa, size, hva, add,
-        memory_region_is_rom(mr), mr->name);
+        memory_region_is_rom(mr) || romd, mr->name);
 }
 
 static void
