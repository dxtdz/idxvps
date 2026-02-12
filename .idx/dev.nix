{ pkgs, ... }: {
  packages = with pkgs; [
    qemu_full
    rclone
    wget
    bore-cli
    util-linux
    jq
    curl
  ];

  idx.workspace.onStart = {
    setup-and-run = ''
      mkdir -p /home/user/windows-idx
      chmod +x run.sh
      bash run.sh
    '';
  };
}  
