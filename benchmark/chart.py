import matplotlib.pyplot as plt
import numpy as np
import csv
import seaborn as sns

class PlotOption():
  def __init__(self, color, label):
    self.xdata = []
    self.ydata = []
    self.color = color
    self.label = label

def load(filename, color, label):
  opt = PlotOption(color, label)
  with open(filename) as f:
    fcsv = csv.reader(f)
    headers = next(fcsv)
    i = 0
    for row in fcsv:
      i = i + 1
      opt.xdata.append(i)
      opt.ydata.append(float(row[0]))
  return opt

def save(optList, afig, bfig):
  plt.xlabel("Request") 
  plt.ylabel("Time(ms)")  
  plt.title("Benchmark - Response Time") 
  plt.gcf().set_size_inches(8, 5)

  for opt in optList:
    plt.plot(opt.xdata, opt.ydata, "b--", color=opt.color, label=opt.label, linewidth=1)
  plt.savefig(afig)
  plt.clf()

  for opt in optList:
    sns.kdeplot(opt.ydata, shade=True, color=opt.color, label=opt.label, alpha=.3) 
  plt.savefig(bfig)
  plt.clf()

def main():
  stdOpt = load("benchmark_std.csv", "green", "std")
  nktOpt = load("benchmark_nkt.csv", "blue", "nkt")
  save([nktOpt, stdOpt], 'chart_line.png', 'chart_sns.png')

main()