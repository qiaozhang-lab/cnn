'''
 @Author: Qiao Zhang
 @Date: 2025-12-17 14:48:32
 @LastEditTime: 2025-12-18 20:37:22
 @LastEditors: Qiao Zhang
 @Description: Download dataset and train model
 @FilePath: /cnn/model/src/LeNet/train.py
'''

# Import library
import torch
from torch.utils.data import DataLoader
import torchvision
from torchvision import transforms

from LeNet5 import LeNet5

def main():
    # 1. Data preprocess
    trans = transforms.ToTensor()

    # 2. Download/ Load dataset
    print("Loading data ...")
    # Note: please make sure the download path is right
    mnist_train = torchvision.datasets.MNIST(
        root="../../data", train=True, transform=trans, download=True
    )
    mnist_test = torchvision.datasets.MNIST(
        root="../../data", train=False, transform=trans, download=True
    )

    # 3. Loading DataLoader
    train_iter = DataLoader(mnist_train, batch_size=256, shuffle=True)
    test_iter  = DataLoader(mnist_test, batch_size=256, shuffle=False)

    # 4. Instantiate Model
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Use the device :{device}")
    print(f"Loading Model to {device}")
    net    = LeNet5().to(device)
    print("Load Model finished!")

    # 5. define loss function and optimizer
    loss = torch.nn.CrossEntropyLoss()
    optimizer = torch.optim.Adam(net.parameters(), lr=0.001)

    # 6. Start training
    print("Starting training ...")
    for epoch in range(10):
        # turn on the train mode
        net.train()
        running_loss = 0.0
        for X, y in train_iter:
            X, y = X.to(device), y.to(device)# Loading data to device
            l = loss(net(X), y)# Calculate loss
            optimizer.zero_grad()# Clear gradient
            l.backward()# backward to calculate gradient
            optimizer.step()# call step(), modify in-place the parameter tensor of optimizer
            running_loss += l.item()# don't put tensor into running_loss
            pass
        print(f"Epoch {epoch+1} finished，Avg Loss: {running_loss / len(train_iter):.4f}")
        pass

    torch.save(net.state_dict(), "lenet_weights.pth")
    print("Model saved.")
    pass

if __name__ == "__main__":
    main()
    pass

