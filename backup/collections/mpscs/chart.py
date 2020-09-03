import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import csv
import seaborn as sns

sns.set(style="darkgrid")
dataset = dict({
  'cap': [4, 1024, 4096, 8192, 16384, 32768] 
})

for path, k in [
  ("mpsc_spin.csv", "spin"),
  ("mpsc_pipe.csv", "pipe"),
  ("mpsc_chan.csv", "chan"),
  ("mpsc_cond.csv", "cond")
]:
  xdata = [] # 工作线程迭代次数
  ydata = [] # 出现重排序次数

  with open(path) as f:
    fcsv = csv.reader(f)
    headers = next(fcsv)
    for row in fcsv:
      xdata.append(float(row[0]))
      ydata.append(float(row[1]))

  dataset[k] = ydata

df = pd.DataFrame(dataset)
df = df.melt('cap', var_name='', value_name='time')

g = sns.relplot(
  x="cap", 
  y="time", 
  hue='',
  height=8, 
  linewidth=2, 
  aspect=1.3, 
  kind="line", 
  data=df
)
g.fig.autofmt_xdate() 

plt.savefig('mpsc.png')