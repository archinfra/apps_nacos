# apps_nacos

Nacos 单点部署离线交付仓库。

这次改造沿用了你现有的业务默认值，没有升级 Nacos 版本，核心目标是把它整理成和 MySQL / Redis / MinIO 一样的交付方式：

- 多架构离线 `.run` 包
- `install|uninstall|status|help` 统一入口
- GitHub Actions 自动构建 `amd64` / `arm64`
- tag 自动产出 release 资产

## 保留的默认值

- 命名空间：`aict`
- 镜像：`sealos.hub:5000/kube4/nacos-server:v2.3.0-slim`
- MySQL 默认地址：`mysql.aict:3306`
- MySQL 默认库：`frame_nacos_demo`
- MySQL 默认用户：`root`
- 副本数：`1`
- Service 类型：`NodePort`
- 端口：`8848 -> 30081`，`9848 -> 30930`

## 构建

```bash
./build.sh --arch amd64
./build.sh --arch arm64
./build.sh --arch all
```

产物位于 `dist/`：

- `nacos-installer-amd64.run`
- `nacos-installer-amd64.run.sha256`
- `nacos-installer-arm64.run`
- `nacos-installer-arm64.run.sha256`

## 使用

```bash
./nacos-installer-amd64.run install \
  --mysql-password '<MYSQL_PASSWORD>' \
  -y
```

如果目标仓库里已经有镜像：

```bash
./nacos-installer-amd64.run install \
  --mysql-password '<MYSQL_PASSWORD>' \
  --skip-image-prepare \
  -y
```

如果要启用 Prometheus 抓取：

```bash
./nacos-installer-amd64.run install \
  --mysql-password '<MYSQL_PASSWORD>' \
  --enable-servicemonitor \
  -y
```

## GitHub Actions

- `push` 到 `main` / `master`：构建多架构离线包
- `push` tag `v*`：构建并发布 GitHub Release
- `workflow_dispatch`：手动触发

## 说明

- 运行时不依赖 `jq`
- `ServiceMonitor` 默认关闭，不会改变你现有部署默认行为
- 如果集群未安装 Prometheus Operator CRD，安装器会自动跳过 `ServiceMonitor`
