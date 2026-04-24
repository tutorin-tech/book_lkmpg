// SPDX-License-Identifier: GPL-2.0
/*
 * dma.c - Minimal DMA API demonstration using a synthetic platform device.
 *
 * This module does not drive real hardware. It exists to show the shape of a
 * modern DMA-capable probe path: set the DMA mask, allocate coherent memory,
 * create a streaming mapping, and tear it all down cleanly.
 */

#include <linux/dma-mapping.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/slab.h>
#include <linux/version.h>

static unsigned int coherent_size = PAGE_SIZE;
module_param(coherent_size, uint, 0444);
MODULE_PARM_DESC(coherent_size, "Size of the coherent DMA buffer");

static unsigned int streaming_size = PAGE_SIZE;
module_param(streaming_size, uint, 0444);
MODULE_PARM_DESC(streaming_size, "Size of the streaming DMA buffer");

static u64 dma_demo_mask = DMA_BIT_MASK(32);

struct dma_demo_dev {
    void *coherent_buf;
    dma_addr_t coherent_handle;
    void *streaming_buf;
    dma_addr_t streaming_handle;
    size_t coherent_len;
    size_t streaming_len;
};

static int dma_demo_probe(struct platform_device *pdev)
{
    struct device *dev = &pdev->dev;
    struct dma_demo_dev *demo;
    int ret;

    ret = dma_set_mask_and_coherent(dev, DMA_BIT_MASK(32));
    if (ret)
        return dev_err_probe(dev, ret, "failed to set DMA mask\n");

    demo = devm_kzalloc(dev, sizeof(*demo), GFP_KERNEL);
    if (!demo)
        return -ENOMEM;

    demo->coherent_len = coherent_size;
    demo->streaming_len = streaming_size;

    demo->coherent_buf = dmam_alloc_coherent(
        dev, demo->coherent_len, &demo->coherent_handle, GFP_KERNEL);
    if (!demo->coherent_buf)
        return dev_err_probe(dev, -ENOMEM,
                             "failed to allocate coherent buffer\n");

    demo->streaming_buf = devm_kzalloc(dev, demo->streaming_len, GFP_KERNEL);
    if (!demo->streaming_buf)
        return -ENOMEM;

    memset(demo->streaming_buf, 0x5a, demo->streaming_len);

    demo->streaming_handle = dma_map_single(dev, demo->streaming_buf,
                                            demo->streaming_len, DMA_TO_DEVICE);
    if (dma_mapping_error(dev, demo->streaming_handle))
        return dev_err_probe(dev, -EIO, "failed to map streaming buffer\n");

    dma_unmap_single(dev, demo->streaming_handle, demo->streaming_len,
                     DMA_TO_DEVICE);

    platform_set_drvdata(pdev, demo);

    dev_info(dev, "coherent=%pad/%zu streaming=%zu DMA mask=0x%llx\n",
             &demo->coherent_handle, demo->coherent_len, demo->streaming_len,
             (unsigned long long)*dev->dma_mask);

    return 0;
}

/*
 * The .remove callback changed from int to void return in Linux 6.11.
 * Between 5.18 and 6.10 the void variant was spelled .remove_new while
 * .remove still returned int.  On 5.10-5.17 only .remove (int) exists.
 */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 18, 0)
static void dma_demo_remove(struct platform_device *pdev)
{
    dev_info(&pdev->dev, "DMA demo removed\n");
}
#else
static int dma_demo_remove(struct platform_device *pdev)
{
    dev_info(&pdev->dev, "DMA demo removed\n");

    return 0;
}
#endif

static struct platform_driver dma_demo_driver = {
	.probe = dma_demo_probe,
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 11, 0)
	.remove = dma_demo_remove,
#elif LINUX_VERSION_CODE >= KERNEL_VERSION(5, 18, 0)
	.remove_new = dma_demo_remove,
#else
	.remove = dma_demo_remove,
#endif
	.driver = {
		.name = "lkmpg_dma_demo",
	},
};

static struct platform_device *dma_demo_pdev;

static int __init dma_demo_init(void)
{
    int ret;

    dma_demo_pdev =
        platform_device_alloc("lkmpg_dma_demo", PLATFORM_DEVID_NONE);
    if (!dma_demo_pdev)
        return -ENOMEM;

    dma_demo_pdev->dev.dma_mask = &dma_demo_mask;
    dma_demo_pdev->dev.coherent_dma_mask = DMA_BIT_MASK(32);

    ret = platform_device_add(dma_demo_pdev);
    if (ret) {
        platform_device_put(dma_demo_pdev);
        return ret;
    }

    ret = platform_driver_register(&dma_demo_driver);
    if (ret) {
        platform_device_unregister(dma_demo_pdev);
        return ret;
    }

    return 0;
}

static void __exit dma_demo_exit(void)
{
    platform_driver_unregister(&dma_demo_driver);
    platform_device_unregister(dma_demo_pdev);
}

module_init(dma_demo_init);
module_exit(dma_demo_exit);

MODULE_DESCRIPTION("LKMPG DMA API demo module");
MODULE_LICENSE("GPL");
