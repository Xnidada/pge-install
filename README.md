# pge-install
这是一个一键安装Prometheus、Grafana和Node Exporter脚本

Prometheus、Grafana为基于Docker进行部署

Node Exporter为二进制部署

# 使用方法
```
git clone https://github.com/Xnidada/pge-install.git
cd pge-install
bash pge-install.sh
```
进行选择即可,目前适配了X86架构的LINUX
```
1) 更换系统源和Docker源
2) 生成Prometheus配置文件
3) 安装与启动Grafana
4) 被监控节点安装Node Exporter
5) 添加被监控节点
6) 安装与启动Prometheus
7) 一键部署监控节点 (执行1,2,3,6)
8) 一键部署被监控节点 (执行1,4)
s) 显示服务状态
c) 检测依赖命令
q) 退出
```

<a href="https://star-history.com/#Xnidada/pge-install&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Xnidada/pge-install&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Xnidada/pge-install&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Xnidada/pge-install&type=Date" />
 </picture>
</a>

**如果觉得这个项目不错对您有所帮助的话，请点击仓库右上角的 ⭐ 并分享给更多的朋友。**
