# apps_nacos

Nacos 单点部署离线交付仓库。

这套仓库沿用你现有的 Nacos 版本和业务默认值，只把交付方式整理成和 MySQL、Redis、MinIO 一致的模式：

- 多架构离线 `.run` 包，支持 `amd64` 和 `arm64`
- 统一入口：`install|uninstall|status|help`
- GitHub Actions 自动构建
- tag 自动发布 GitHub Release
- 安装时可选执行 Nacos 数据库基线初始化
- 安装时可选导入最新版 `cmict-share.yaml`

## 当前默认值

- 命名空间：`aict`
- 镜像：`sealos.hub:5000/kube4/nacos-server:v2.3.0-slim`
- MySQL 主机：`mysql-0.mysql.aict`
- MySQL 端口：`3306`
- MySQL 数据库：`frame_nacos_demo`
- MySQL 用户：`root`
- 副本数：`1`
- Service 类型：`NodePort`
- Nacos HTTP NodePort：`30094`
- Nacos gRPC 端口暴露：`9848 -> 30930`
- metrics：默认开启
- ServiceMonitor：默认开启
- 数据库基线初始化：默认开启
- `cmict-share.yaml` 导入：默认开启

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

按默认值安装：

```bash
./nacos-installer-amd64.run install \
  --mysql-password '<MYSQL_PASSWORD>' \
  -y
```

显式指定 HTTP NodePort：

```bash
./nacos-installer-amd64.run install \
  --mysql-password '<MYSQL_PASSWORD>' \
  --node-port 30094 \
  -y
```

如果目标仓库里已经有镜像：

```bash
./nacos-installer-amd64.run install \
  --mysql-password '<MYSQL_PASSWORD>' \
  --skip-image-prepare \
  -y
```

显式关闭监控：

```bash
./nacos-installer-amd64.run install \
  --mysql-password '<MYSQL_PASSWORD>' \
  --disable-metrics \
  -y
```

只部署 Nacos，不执行数据库初始化：

```bash
./nacos-installer-amd64.run install \
  --mysql-password '<MYSQL_PASSWORD>' \
  --disable-db-bootstrap \
  --disable-cmict-share-import \
  -y
```

## 基线资产

- `frame_nacos_demo.sql`
  这是清洗后的标准 SQL：
  - 已改成幂等导入，不再包含 `DROP TABLE`
  - 去掉了 `his_config_info` 历史数据
  - 不再把业务配置固化进 `config_info`
  - `cmict-share.yaml` 改为安装时单独导入，始终以文件最新版为准
- `cmict-share.yaml`
  这是安装器默认导入的最新版共享配置
- `tools/normalize_nacos_sql.py`
  后续如果你替换了原始 dump，可以用这个脚本重新生成标准 SQL
- `import-nacos.sh`
  手工重跑基线导入时可直接使用这个脚本，不必重新安装 Nacos

## 安装流程

`install` 现在默认会按这个顺序执行：

1. 提取离线 payload 并准备镜像
2. 用 MySQL helper Job 初始化 `frame_nacos_demo` 库和标准表结构
3. 把 `cmict-share.yaml` 写入 `config_info`
4. 部署 Nacos
5. 等待 Deployment Ready

## GitHub Actions

- `push` 到 `main` 或 `master`：构建多架构离线包
- `push` tag `v*`：构建并发布 GitHub Release
- `workflow_dispatch`：手动触发

## 说明

- 运行时不依赖 `jq`
- payload 提取逻辑已做稳健化处理，避免 `.run` 包在目标机上出现 `gzip: stdin: not in gzip format`
- 如果集群未安装 Prometheus Operator CRD，安装器会自动跳过 `ServiceMonitor`
