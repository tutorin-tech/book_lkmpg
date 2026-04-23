/*
 * hello-debugfs.c - Export simple values through debugfs.
 */
#include <linux/debugfs.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/printk.h>

MODULE_DESCRIPTION("Export simple values through debugfs");
MODULE_LICENSE("GPL");

#define DEBUGFS_DIR "lkmpg_debugfs"

static struct dentry *debugfs_dir;

static u32 debug_value = 42;
static bool debug_enabled = true;

module_param(debug_value, uint, 0600);
MODULE_PARM_DESC(debug_value, "Value exported through both sysfs and debugfs");

module_param(debug_enabled, bool, 0600);
MODULE_PARM_DESC(debug_enabled, "Enable or disable the example flag");

static int __init hello_debugfs_init(void)
{
    debugfs_dir = debugfs_create_dir(DEBUGFS_DIR, NULL);

    debugfs_create_u32("debug_value", 0600, debugfs_dir, &debug_value);
    debugfs_create_bool("debug_enabled", 0600, debugfs_dir, &debug_enabled);

    pr_info("debugfs interface registered under /sys/kernel/debug/%s\n",
            DEBUGFS_DIR);
    return 0;
}

static void __exit hello_debugfs_exit(void)
{
    debugfs_remove_recursive(debugfs_dir);
    pr_info("debugfs example removed\n");
}

module_init(hello_debugfs_init);
module_exit(hello_debugfs_exit);
