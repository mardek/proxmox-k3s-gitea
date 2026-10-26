# Binary Assets

These binary files from the session zip are **not included** in the GitHub repo due to API upload size limitations.

Upload them manually via GitHub web UI or `git push`:

| File | Size | Description |
|------|------|-------------|
| `martial_ndeko_folligan_resume.pdf` | 24 KB | Resume PDF |
| `aws-free-plan-2026-10-20.png` | 12 KB | AWS billing screenshot |
| `OpenNet DevSecOps Engineer.pdf` | 339 KB | Job description PDF |

To add them locally:
```bash
git clone https://github.com/mardek/proxmox-k3s-gitea.git
cd proxmox-k3s-gitea/docs/assets
cp /path/to/your/files .
git add .
git commit -m "Add binary assets"
git push
```
