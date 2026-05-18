import matplotlib.pyplot as plt
import matplotlib.patches as patches
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
import numpy as np

# Create figure
fig, ax = plt.subplots(1, 1, figsize=(10, 4))

# Colors (similar to reference image)
main_color = '#B8D4E8'      # Light blue background for main
feature_color = '#C8E6C9'   # Light green background for feature
commit_color = '#4A90D9'    # Blue for commits
line_color = '#333333'      # Dark for arrows/lines
bg_color = 'white'

# Set background
fig.patch.set_facecolor(bg_color)
ax.set_facecolor(bg_color)

# Dimensions
box_height = 0.6
y_main = 2.0
y_feature = 0.8
x_start = 1
x_end = 9

# Draw background boxes
main_box = FancyBboxPatch((x_start, y_main - box_height/2), x_end - x_start, box_height,
                          boxstyle="round,pad=0.02,rounding_size=0.15",
                          facecolor=main_color, edgecolor='none', zorder=1)
ax.add_patch(main_box)

feature_box = FancyBboxPatch((x_start, y_feature - box_height/2), x_end - x_start, box_height,
                             boxstyle="round,pad=0.02,rounding_size=0.15",
                             facecolor=feature_color, edgecolor='none', zorder=1)
ax.add_patch(feature_box)

# Branch labels
ax.text(0.5, y_main, 'main', fontsize=12, fontweight='bold', va='center', ha='right', color='#333')
ax.text(0.5, y_feature, 'feature', fontsize=12, fontweight='bold', va='center', ha='right', color='#333')

# Commits on main branch
main_commits = [2, 4, 7, 8.5]
for x in main_commits:
    circle = plt.Circle((x, y_main), 0.18, color=commit_color, zorder=3)
    ax.add_patch(circle)

# Commits on feature branch
feature_commits = [4.5, 6]
for x in feature_commits:
    circle = plt.Circle((x, y_feature), 0.18, color=commit_color, zorder=3)
    ax.add_patch(circle)

# Arrows connecting commits on main
ax.annotate('', xy=(3.8, y_main), xytext=(2.2, y_main),
            arrowprops=dict(arrowstyle='->', color=line_color, lw=2))
ax.annotate('', xy=(6.8, y_main), xytext=(4.2, y_main),
            arrowprops=dict(arrowstyle='->', color=line_color, lw=2))
ax.annotate('', xy=(8.3, y_main), xytext=(7.2, y_main),
            arrowprops=dict(arrowstyle='->', color=line_color, lw=2))

# Arrows on feature branch
ax.annotate('', xy=(5.8, y_feature), xytext=(4.7, y_feature),
            arrowprops=dict(arrowstyle='->', color=line_color, lw=2))

# Branch arrow (main -> feature)
ax.annotate('', xy=(4.5, y_feature + 0.25), xytext=(4, y_main - 0.25),
            arrowprops=dict(arrowstyle='->', color=line_color, lw=2,
                          connectionstyle='arc3,rad=-0.3'))

# Merge arrow (feature -> main)
ax.annotate('', xy=(7, y_main - 0.25), xytext=(6, y_feature + 0.25),
            arrowprops=dict(arrowstyle='->', color=line_color, lw=2,
                          connectionstyle='arc3,rad=-0.3'))

# Labels for branch and merge
ax.text(3.5, 1.5, 'branch', fontsize=10, ha='center', color='#555')
ax.text(7, 1.5, 'merge', fontsize=10, ha='center', color='#555')

# Time arrow
ax.annotate('', xy=(9.5, 0.15), xytext=(0.5, 0.15),
            arrowprops=dict(arrowstyle='->', color='#888', lw=1.5))
ax.text(5, -0.05, 'time', fontsize=11, ha='center', color='#888')

# Title
ax.text(5, 3.0, 'GIT BRANCHES', fontsize=18, fontweight='bold', ha='center', color='#333')

# Set limits and remove axes
ax.set_xlim(0, 10)
ax.set_ylim(-0.3, 3.3)
ax.set_aspect('equal')
ax.axis('off')

# Save
plt.tight_layout()
plt.savefig('c:/GCAM/gcamreport/images/git-branches.png', dpi=150,
            bbox_inches='tight', facecolor=bg_color, edgecolor='none')
plt.close()

print("Branch diagram saved!")
