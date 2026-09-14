# flake.module.nix — project-specific flake-parts customizations.
#
# seihou does NOT manage this file: it is never regenerated or overwritten by
# `seihou run` or by module migrations, so changes here survive template
# upgrades without conflict. See flake.module.nix.example for the full reference.
{ ... }:
{
  perSystem = { pkgs, ... }: {
    # Preserved from the pre-adoption dev shell (nix/haskell.nix used to list
    # pkgs.xz directly). Kept here so template upgrades stay conflict-free.
    haskellProject.extraDevPackages = [ pkgs.xz ];
  };
}
