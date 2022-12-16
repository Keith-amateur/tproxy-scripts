#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <cap-ng.h>
#include <sys/prctl.h>
#include <linux/capability.h>

#define PR_CAP_AMBIENET 47
#define PR_CAP_AMBIENT_IS_SET 1
#define PR_CAP_AMBIENET_RAISE 2
#define PR_CAP_AMBIENET_LOWER 3
#define PR_CAP_AMBIENET_CLEAR_ALL 4

static void set_ambient_cap(int cap) {
	int rc;

	capng_get_caps_process();
	rc = capng_update(CAPNG_ADD, CAPNG_INHERITABLE, cap);
	if (rc) {
		printf("Can not add inheritable cap\n");
		exit(2);
	}
	capng_apply(CAPNG_SELECT_CAPS);
	if (prctl(PR_CAP_AMBIENET, PR_CAP_AMBIENET_RAISE, cap, 0, 0)) {
		perror("Can not set cap");
		exit(1);
	}
}

int main(int argc, char *argv[]) {
	char *bash_argv[] = {"bash", "-l", NULL};
	set_ambient_cap(CAP_NET_BIND_SERVICE);
	set_ambient_cap(CAP_NET_ADMIN);
	printf("Starting bash with CAP_NET_BIND_SERVICE,CAP_NET_ADMIN in ambient\n");	
	if (execv("/bin/bash", bash_argv))
		perror("Cannot exec");
	return 0;
}
