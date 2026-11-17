
# Use Node.js 24 as the base image
FROM node:24

# Set the working directory inside the container
WORKDIR /app

# Copy package files first
COPY package*.json ./

# Install application dependencies
RUN npm ci

# Copy the application source code
COPY . .

# Expose application port
EXPOSE 3000

# Start the Node.js application
CMD ["npm", "start"]
