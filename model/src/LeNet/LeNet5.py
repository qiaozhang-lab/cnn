'''
 @Author: Qiao Zhang
 @Date: 2025-12-17 14:29:49
 @LastEditTime: 2025-12-18 20:08:20
 @LastEditors: Qiao Zhang
 @Description: Model a LeNet5 model
 @FilePath: /cnn/model/src/LeNet/LeNet5.py
'''
import torch
import torch.nn as nn

# Define a module: LeNet
class LeNet5(nn.Module):
    '''
    A classical LeNet Neural Network: for MNIST dataset:
    Structure: Conv2d -> ReLU -> Pool -> Conv2d -> ReLU -> Pool -> FC -> FC
    '''
    def __init__(self):
        super().__init__()# Init father module attribute

        #===============================
        # Start to establish Module layers
        #===============================

        # feature extraction
        self.features = nn.Sequential(
            # [Batch, 1, 28, 28] -> [Batch, 6, 28, 28]
            nn.Conv2d(1, 6, kernel_size=5, padding=2),
            nn.ReLU(),
            # [Batch, 6, 28, 28] -> [Batch, 6, 14, 14]
            nn.MaxPool2d(kernel_size=2,stride=2),
            # [Batch, 6, 14, 14] -> [Batch, 16, 10, 10]
            nn.Conv2d(6, 16, kernel_size=5),
            nn.ReLU(),
            # [Batch, 16, 10, 10] -> [Batch, 16, 5, 5]
            nn.MaxPool2d(kernel_size=2, stride=2)
        )

        # Classifier head
        self.classifier = nn.Sequential(
            # [Batch, 16, 5, 5] -> [Batch, 16*5*5]
            nn.Flatten(),
            # [Batch, 400] -> [Batch, 120]
            nn.Linear(16*5*5, 120),
            nn.ReLU(inplace=True),
            # [Batch, 120] -> [Batch, 84]
            nn.Linear(120, 84),
            nn.ReLU(inplace=True),
            # [Batch, 84] -> [Batch, 10]
            nn.Linear(84, 10)
        )

    def forward(self, x):
        x = self.features(x)
        x = self.classifier(x)
        return x




