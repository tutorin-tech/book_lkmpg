/*
 * hello-debugfs-file.c - Custom debugfs file and blob examples.
 */
#include <linux/debugfs.h>
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/printk.h>
#include <linux/string.h>
#include <linux/uaccess.h>

MODULE_DESCRIPTION("Custom debugfs file and blob examples");
MODULE_LICENSE("GPL");

#define DEBUGFS_DIR "lkmpg_debugfs_file"
#define MESSAGE_MAX_LEN 128

static struct dentry *debugfs_dir;
static DEFINE_MUTEX(message_lock);
static char message[MESSAGE_MAX_LEN] = "debugfs says hello\n";
static size_t message_len = sizeof("debugfs says hello\n") - 1;

static const char blob_data[] =
    "This blob is read-only and exported with debugfs_create_blob().\n";
static struct debugfs_blob_wrapper debug_blob = {
    .data = (void *)blob_data,
    .size = sizeof(blob_data) - 1,
};

static ssize_t message_read(struct file *file, char __user *buffer, size_t len,
                            loff_t *ppos)
{
    ssize_t ret;

    mutex_lock(&message_lock);
    ret = simple_read_from_buffer(buffer, len, ppos, message, message_len);
    mutex_unlock(&message_lock);

    return ret;
}

static ssize_t message_write(struct file *file, const char __user *buffer,
                             size_t len, loff_t *ppos)
{
    ssize_t copied;

    if (*ppos != 0)
        return -EINVAL;

    mutex_lock(&message_lock);
    copied =
        simple_write_to_buffer(message, sizeof(message) - 1, ppos, buffer, len);
    if (copied > 0) {
        message_len = *ppos;
        message[message_len] = '\0';
    }
    mutex_unlock(&message_lock);

    return copied;
}

static const struct file_operations message_fops = {
    .owner = THIS_MODULE,
    .read = message_read,
    .write = message_write,
    .llseek = default_llseek,
};

static int __init hello_debugfs_file_init(void)
{
    debugfs_dir = debugfs_create_dir(DEBUGFS_DIR, NULL);

    debugfs_create_file("message", 0600, debugfs_dir, NULL, &message_fops);
    debugfs_create_blob("blob", 0400, debugfs_dir, &debug_blob);

    pr_info("debugfs file example registered under /sys/kernel/debug/%s\n",
            DEBUGFS_DIR);
    return 0;
}

static void __exit hello_debugfs_file_exit(void)
{
    debugfs_remove_recursive(debugfs_dir);
    pr_info("debugfs file example removed\n");
}

module_init(hello_debugfs_file_init);
module_exit(hello_debugfs_file_exit);
