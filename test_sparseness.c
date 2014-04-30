/*
 * test_sparseness.c - creates a sparse file and checks whether the
 *                     file system returns zeros for unwritten bytes
 * usage: gcc test_sparseness.c -std=c99 && ./a.out
 */

#define _BSD_SOURCE 
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/wait.h>

#define NBLOCKS 1024*1024

int main (int argc, char **argv)
{
  char buf[1] = {'X'};
  char filename[] = "zero-file-XXXXXX";
  int fd = mkstemp(filename);
  if (fd < 0) {
    perror(argv[0]);
    exit(1);
  }

  off_t filesize = NBLOCKS * 512L;
  if (lseek(fd, filesize - 1, SEEK_CUR) == (off_t) - 1) {    // create a file with a hole
    perror(argv[0]);
    exit(1);
  }
  if (write(fd, buf, 1) != 1) {
    printf("failed to write\n");
    perror(argv[0]);
    exit(1);
  }
  fsync(fd);

  int pid = fork();
  if (pid < 0) {
    perror(argv[0]);
    exit(1);
  }

  if (pid == 0) {
    close (fd);
    fd = open(filename, O_RDONLY);
    if (fd < 0) {
      perror(argv[0]);
      exit(1);
    }
    struct stat st;
    if (fstat(fd, &st) != 0) {
      perror(argv[0]);
      exit(1);
    }
    printf("child process opened file %s of size %ld\n", filename, st.st_size);

    for (long i=0; i<(filesize - 1); i++) {
      ssize_t r = read(fd, buf, 1);
      if (r != 1) {
	printf("failed to read (%ld != 1) in position %ld (size %ld)\n", r, i, filesize);
	perror(argv[0]);
	exit(1);
      }
      if (buf[0] != '\0') {
	printf("read non-zero in position %ld (size %ld)\n", i, filesize);
	exit(1);
      }
      if ((i % (filesize / 100)) == 0) {
	printf("checked %ld bytes, %g%%\n", i, ((double)i / (double)filesize) * 100.0);
      }
    }
    exit(0);
  }
  
  int status;
  waitpid(pid, &status, 0);
  
  return status;
}
