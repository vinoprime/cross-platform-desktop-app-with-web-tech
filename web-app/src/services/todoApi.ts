import type { TodoItem } from "../types/todo";

const configuredBaseUrl = import.meta.env.VITE_TODO_API_BASE_URL?.trim();
const apiBaseUrl = configuredBaseUrl && configuredBaseUrl.length > 0
    ? configuredBaseUrl.replace(/\/$/, "")
    : "https://jsonplaceholder.typicode.com";

const todosEndpoint = `${apiBaseUrl}/todos?_limit=12`;

export async function fetchTodos(): Promise<TodoItem[]> {
    const response = await fetch(todosEndpoint, {
        headers: {
            Accept: "application/json",
        },
    });

    if (!response.ok) {
        throw new Error(`ToDo request failed with status ${response.status}`);
    }

    return (await response.json()) as TodoItem[];
}
