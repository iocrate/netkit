import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import csv
import seaborn as sns

sns.set(style="darkgrid")

xdata = [] # 工作线程迭代次数
ydata = [] # 出现重排序次数

with open("reordering.csv") as f:
  fcsv = csv.reader(f)
  headers = next(fcsv)
  for row in fcsv:
    xdata.append(float(row[1]))
    ydata.append(float(row[0]))

df = pd.DataFrame(dict(counter=xdata, n=ydata))

g = sns.relplot(
  x="counter", 
  y="n", 
  height=4, 
  linewidth=2, 
  aspect=1.3, 
  kind="line", 
  data=df
)
g.fig.autofmt_xdate() 
plt.savefig('reordering.png')