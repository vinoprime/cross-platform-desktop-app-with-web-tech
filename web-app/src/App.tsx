import { useEffect, useState } from "react";
import "./App.css";
import { fetchTodos } from "./services/todoApi";
import type { TodoItem } from "./types/todo";

function App() {
  const [items, setItems] = useState<TodoItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const load = async () => {
      try {
        const todoItems = await fetchTodos();
        setItems(todoItems);
      } catch (err) {
        const message =
          err instanceof Error ? err.message : "Failed to load todo list";
        setError(message);
      } finally {
        setLoading(false);
      }
    };

    void load();
  }, []);

  return (
    <main className="shell">
      <section className="panel">
        <h1>ToDo List</h1>

        {loading && <p className="state">Loading todos...</p>}

        {error && !loading && <p className="state error">{error}</p>}

        {!loading && !error && items.length === 0 && (
          <p className="state">No todo items available.</p>
        )}

        {!loading && !error && items.length > 0 && (
          <ul className="todo-list">
            {items.map((item) => (
              <li key={item.id} className="todo-item">
                <div>
                  <strong>{item.title}</strong>
                  <p>User: {item.userId}</p>
                </div>
                <span
                  className={item.completed ? "status done" : "status pending"}
                >
                  {item.completed ? "Done" : "Pending"}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </main>
  );
}

export default App;
