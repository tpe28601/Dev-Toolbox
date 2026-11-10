# tools/

三個工具以 git submodule 的方式放在這裡，每個都指向該工具 repo 的 tag。

第一次加入（各工具 repo 建好、打好第一個 tag 之後執行一次）：

```bat
git submodule add https://github.com/tpe28601/git-ref-manager.git tools/Git-Ref-Manager
git submodule add https://github.com/tpe28601/cfg-manager.git tools/Opencode-Cfg-Manager
git submodule add https://github.com/tpe28601/key-manager.git tools/Key-Manager
cd tools/Git-Ref-Manager && git checkout v1.1.1 && cd ../..
git add .gitmodules tools && git commit -m "Add tools as submodules"
```

repo 是私人的時候，clone 會要求登入 GitHub；Git for Windows 的 Credential Manager 會自動跳出登入視窗。

在 submodule 裡開發前，先 `git switch main`，避免在 detached HEAD 上 commit。
