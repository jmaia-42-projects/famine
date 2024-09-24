#include <fcntl.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <stdint.h>
#include <unistd.h>

#define _GNU_SOURCE
#include <dirent.h>

struct linux_dirent64 {
	uint64_t d_ino;
	uint64_t d_off;
	unsigned short d_reclen;
	unsigned char d_type;
	char d_name[];
};

#define BUF_SIZE 200

int main()
{
	struct linux_dirent64 *test;
	uint8_t buf[BUF_SIZE];
	uint8_t *cur_ptr;
	int ret;

	int fd = open("/tmp/coucou", O_RDONLY);
	if (fd == -1)
		return 1;
	while ((ret = syscall(SYS_getdents64, fd, buf, BUF_SIZE)) > 0)
	{
		cur_ptr = buf;
		while (ret > 0)
		{
			test = (struct linux_dirent64 *) cur_ptr;
			printf("Name: %s\n", test->d_name);
			printf("Ret: %d\n", ret);
			cur_ptr += test->d_reclen;
			ret -= test->d_reclen;
		}
	}
	printf("Ret: %d\n", ret);
}
